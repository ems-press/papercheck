-- Papercheck
-- Version 0.3.1 (2022/08/05)
-- By Simon Winter
-- https://github.com/ems-press/papercheck

-- tested on
--  Windows 10 + Lua 5.1.5
--  Linux + Lua 5.4.4

-- Open points marked with TODO.

local lfs = require 'lfs'

-- Add path of main file to package path.
local path = arg[0]
path = path:gsub('(.-)papercheck.lua$', '%1')
package.path = path..'?.lua;'..package.path

local F = require 'papercheckfunctions'

local input_path = arg[1] -- path of the input tex file

local folder, input
local texpattern = '(.-)%.tex$'
-- Check if input_path is a full path (with separator)
-- or a file name (no separator).
if input_path:find(F.sep) then
  folder, input = input_path:match(F.path('(.+)', texpattern))
  -- Example:
  --  F.path('(.+)', texpattern)  --> (.+)\\(.-)%.tex$
  --  folder                      --> C:\articles
  --  input                       --> mainfile
else
  folder = lfs.currentdir()
  input = input_path:match(texpattern)
end
assert(input, "\n*** File name not recognized. Note that the path must not contain any spaces. ***\n\n")
-- Save current working directory.
-- local cwd = lfs.currentdir()
-- Change to folder of input file.
lfs.chdir(folder)

local texcode = F.read_file(input..'.tex')
assert(texcode, "\n*** File "..input..".tex missing! ***\n\n")
local auxcode = F.read_file(input..'.aux')

if not auxcode then
  auxcode = ""
  print("\n*** File "..input..".aux missing!")
  print("    Create it and run Papercheck again. ***\n\n")
end

-- Replace \include{...} and \input{...} by the respective content.
-- TODO: Allow also other file types than .tex.
-- TODO: Works only for local files, not everything in TeX's search path.

-- First, replace "\input FILE.tex" by "\input{FILE.tex}".
-- FILE = [%w_%.%-]+
texcode = texcode:gsub('\\input%s*([%w_%.%-]+)%.tex(%A)', '\\input{%1.tex}%2')

-- Input: t = 'include' or 'input'
local function resolveinclude(t)
  -- Remove \include or \input after leading %
  texcode = texcode:gsub('%%%s*\\'..t..'%s*{(.-)}', '')
  local fn = texcode:match('\\'..t..'%s*{(.-)}') -- filename, possibly with '.tex'
  if fn then
    -- Remove '.tex' if exists.
    -- Note that neither \include nor \input require this file extension.
    local fn_noextension = fn:gsub('%.tex$', '')
    local TEX = F.read_file(fn_noextension..'.tex')
    assert(TEX, "\n*** Can't find "..fn_noextension
      ..".tex. Must be in the same folder as the main tex file. ***\n\n")
    texcode = texcode:gsub('\\'..t..'%s*{'..F.escape_lua(fn)..'}', TEX:gsub('%%', '%%%%'), 1)
    print(fn_noextension..".tex included")
    -- \include tex files have an aux file; \input tex files don't.
    if t=='include' then
      local AUX = F.read_file(fn_noextension..'.aux')
      if AUX then
        auxcode = auxcode..'\n'..AUX
      else
        print("\n*** File "..fn_noextension..".aux missing!")
        print("    Create it and run Papercheck again. ***\n\n")
      end
    end
    -- Recursive:
    resolveinclude(t)
  end
end
print("-------------------")
resolveinclude('include')
resolveinclude('input')
print("-------------------\n")

-- Delete all LaTeX comments.
-- N.B.: Don't delete the percent sign \%.
-- Since gsub('([^\\])%%.-\n', '%1\n') doesn't work with sequenced %-lines,
-- first delete all lines starting with % and in a second step all remaining %.
local new = {}
for line in texcode:gmatch('(.-)\n') do
  if not line:match('^%s-%%') then
    new[#new + 1] = line
  end
end
texcode = table.concat(new, '\n')
texcode = texcode:gsub('([^\\])%%.-\n', '%1\n')

-- Delete all labels.
texcode = texcode:gsub('\\label%s*%b{}', '\\label{xxx}')
texcode = texcode:gsub('\\ref%s*%b{}', '\\ref{xxx}')
texcode = texcode:gsub('\\eqref%s*%b{}', '\\eqref{xxx}')
texcode = texcode:gsub('\\cite%s*%b{}', '\\cite{xxx}')
texcode = texcode:gsub('\\cite%s*(%b[])%s*%b{}', '\\cite%1{xxx}')
texcode = texcode:gsub('\\bibitem%s*%b{}', '\\bibitem{xxx}')
texcode = texcode:gsub('\\bibitem%s*%b[]%s*%b{}', '\\bibitem{xxx}')

blankline = false -- must not be local

----------------------------------

local Greeks = {
'alpha','beta','Gamma','gamma','Delta','delta','epsilon','varepsilon',
'zeta','eta','Theta','theta','vartheta','iota','kappa','Lambda','lambda',
'mu','nu','xi','Xi','Pi','pi','varpi','rho','varrho','Sigma','sigma','varsigma',
'tau','Upsilon','upsilon','Phi','phi','varphi','chi','Psi','psi','Omega','omega'}

for i = 1, #Greeks do
  -- \mathbf{\gamma}
  F.patternsearch(texcode,"\\mathbf%s*{?%s*\\"..Greeks[i],
    "\\mathbf{\\"..Greeks[i].."} --> \\mathbold\\"..Greeks[i])
  -- {\bf\gamma}
  F.patternsearch(texcode,"{%s*\\bf%s*\\"..Greeks[i],
    "\\bf\\"..Greeks[i].." --> \\mathbold\\"..Greeks[i])
  -- \mathrm{\gamma}
  F.patternsearch(texcode,"\\mathrm%s*{?%s*\\"..Greeks[i],
    "\\mathrm{\\"..Greeks[i].."} --> \\up"..Greeks[i])
  -- {\rm\Gamma}
  F.patternsearch(texcode,"{%s*\\rm%s*\\"..Greeks[i],
    "\\rm\\"..Greeks[i].." --> \\up"..Greeks[i])
  -- \DeclareMathOperator\mygamma\gamma
  F.patternsearch(texcode,"\\DeclareMathOperator%*?%s*{?\\%a-}?%s*{?[%a@]*\\"..Greeks[i],
    "Don't use \\"..Greeks[i].." in \\DeclareMathOperator")
end

local VarGreeks = {
'Gamma','Delta','Theta','Lambda','Xi','Pi','Sigma','Upsilon','Phi','Psi','Omega'}

for i = 1, #VarGreeks do
  F.patternsearch(texcode,"\\var"..VarGreeks[i], "\\var"..VarGreeks[i].." --?--> \\"..VarGreeks[i])
end
F.add_blankline()

-- Find double words:
F.patternsearch(texcode,"[^%a][Aa][%s\n~]+[Aa][^%a]", "Double word: A/a")
F.repeatedword(texcode)
F.add_blankline()

local bibliography = texcode:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')

if bibliography then
  F.patternsearch(bibliography,"Verlag", "Word 'Verlag' found in the bibliography;"
    .." should be avoided after 'Springer' and 'Birkh\\\"auser'.")
  F.add_blankline()
end

-- Special check for \epsilon vs. \varepsilon:
F.inconsistencysearch(texcode,{"\\epsilon", "\\varepsilon"})
if texcode:match("\\epsilon") and not texcode:match("\\varepsilon") then
  print("\\epsilon --> \\varepsilon\n")
end

-- !!!
-- Now remove the bibliography.
-- !!!
texcode = texcode:gsub('\\begin%s*{thebibliography}.-\\end%s*{thebibliography}', '')

local inconsistency = {
  -- {"\\epsilon", "\\varepsilon"}, -- see above
  {"\\theta", "\\vartheta"},
  {"\\pi", "\\varpi"},
  {"\\rho", "\\varrho"},
  {"\\sigma", "\\varsigma"},
  {"\\phi", "\\varphi"},
  {"\\setminus", "\\smallsetminus", "\\backslash"},
  {"\\emptyset", "\\varnothing"},
  {"[^%a]ker[^%a]", "[^%a]Ker[^%a]"},
  {"[^%a]Im[^%a]", "[^%a]im[^%a]"},
  {"[^%a]Re[^%a]", "[^%a]re[^%a]"},
  {"rhs", "RHS", "right hand side", "right%-hand side"},
  {"lhs", "LHS", "left hand side", "left%-hand side"},
  {"K[%-%s\n~]+theory", "%$K%$[%-%s\n~]+theory"},
  {"K[%-%s\n~]+theory", "\\%(K\\%)[%-%s\n~]+theory"},
  ---
  {"Abelian", "abelian"},
  {"[aA]nalogue", "[aA]nalogs?[^%a]"},
  {"[cC]entre", "[cC]enter"},
  {"Diophantine", "diophantine"},
  {"[dD]isk[s%p\n%s]", "[dD]isc[s%p\n%s]"},
  {"Euclidean", "euclidean"},
  {"[fF]actorises", "[fF]actorizes"},
  {"[fF]ibre", "[fF]iber"},
  {"[fF]ormulas", "[fF]ormulae"},
  {"[hH]omogenous", "[hH]omogeneous"},
  {"[lL]emmas", "[lL]emmata"},
  {"[nN]eighbour", "[nN]eighbor"},
  {"Noetherian", "noetherian"},
  {"[nN]ormalisation", "[nN]ormalization"},
  {"[pP]arametrisation", "[pP]arametrization"},
  {"Riemannian", "riemannian"},
  {"[vV]ertexes", "[vV]ertices"},
  {"[zZ]eros", "[zZ]eroes"},
  ---
}
for i = 1, #inconsistency do
  F.inconsistencysearch(texcode,inconsistency[i])
  F.add_blankline()
end

local hyphenated = {
  {"anti", "homomorphism"},
  {"bi", "linear"},
  {"bi", "section"},
  {"bi", "quotient"},
  {"bi", "invariant"},
  {"blow", "up"},
  {"chain", "complex"},
  {"co", "domain"},
  {"co", "representation"},
  {"cross", "product"},
  {"finite", "dimensional"},
  {"left", "exact"},
  {"long", "standing"},
  {"multi", "index"},
  {"nil", "radical"},
  {"order", "preserving"},
  {"pre", "image"},
  {"pre", "compact"},
  {"pro", "algebraic"},
  {"pull", "back"},
  {"re", "indexing"},
  {"scalar", "valued"},
  {"self", "adjoint"},
  {"self", "induced"},
  {"set", "theoretic"},
  {"set", "up"},
  {"simply", "connected"},
  {"so", "called"},
  {"square", "root"},
  {"star", "shaped"},
  {"straight", "forward"},
  {"square", "free"},
  {"two", "fold"},
  {"two", "sided"},
  {"torsion", "free"},
  {"uni", "tarizability"},
  {"vector", "space"},
  {"zariski", "open"},
}
for i = 1, #hyphenated do
  F.hyphenatedsearch(texcode,hyphenated[i][1],hyphenated[i][2])
  F.add_blankline()
end

local pattern_note = {
  {"[^\\]%.[%s\n~]*\\end%b{}[%s\n~]*where", "'. \\end{...} where' found"},
  {"[^\\]%.[%s\n~]*\\%][%s\n~]*where", "'. \\] where' found"},
  {"%$%s+%$", "Space in-between $ $ correct?"},
  {"\\%)%s+\\%(", "Space in-between \\) \\( correct?"},
  {"%$%(%$", "$($ --> ("},
  {"\\%(%(\\%)", "\\((\\) --> ("},
  {"%$%)%$", "$)$ --> )"},
  {"\\%(%)\\%)", "\\()\\) --> )"},
  {"\\noindent", "\\noindent correct?"},
  {"\\smallskip", "\\smallskip correct?"},
  {"\\medskip", "\\medskip correct?"},
  {"\\bigskip", "\\bigskip correct?"},
  {"\\vspace", "\\vspace correct?"},
  {"\\hspace", "\\hspace correct?"},
  {"\\vskip", "\\vskip correct?"},
  {"\\hskip", "\\hskip correct?"},
  {"\\vfill", "\\vfill correct?"},
  {"\\hfill", "\\hfill correct?"},
  {"\\break", "\\break correct?"},
  {"\\linebreak", "\\linebreak correct?"},
  {"\\small%A", "\\small correct?"},
  {"\\left%A", "\\left correct?"},
  {"\\right%A", "\\right correct?"},
  {"\\theoremstyle{remark}", "\\theoremstyle{remark} --> \\theoremstyle{definition}"},
  {"\\longleftarrow", "\\longleftarrow --?--> \\leftarrow or \\xleftarrow"},
  {"\\longrightarrow", "\\longrightarrow --?--> \\rightarrow or \\xrightarrow"},
  {"\\longmapsto", "\\longmapsto --?--> \\mapsto or \\xmapsto"},
  {"%^'", "^' --?--> '"},
  {"%^{'", "^{' --?--> ' (possibly more than one prime)"},
  {"_[%s\n]*%(", "_( correct?"},
  {"_[%s\n]*%)", "_) correct?"},
  {"_{_", "_{_ --?--> _"},
  {"%^{%^", "^{^ --?--> ^"},
  {"~%s", "Space after ~ correct?"},
  {"[^%.]%.%.[^%.]", ".. (two dots) correct?"},
  {"%.%.%.", "... --?--> \\ldots or \\cdots"},
  {"\\renewcommand%s*\\null", "Do not redefine \\null"},
  {"\\renewcommand%s*\\{\\null", "Do not redefine \\null"},
  {"\\def%s*\\null", "Do not redefine \\null"},
  {"[^`]`s", "Wrong character for apostrophe in `s?"},
  {"%$%$", "$$ found. Regular expression: \\$\\$\\(**\\)\\$\\$ --> \\\\\\[\\0\\\\\\] (or similar)"},
  {"%(\\ref", "(\\ref{...}) found. Regular expression: (\\\\ref\\{\\(*\\)\\}) --> \\\\eqref\\{\\0\\} (or similar)"},
  {"\\pageref", "\\pageref not allowed in journal articles"},
  {"%$[%s\n]*\\footnote", "Avoid footnotemark near $...$ environment"},
  {"\\%)[%s\n]*\\footnote", "Avoid footnotemark near \\(...\\) environment"},
  {"\\limits", "\\limits correct?"},
  {"\\nolimits", "\\nolimits correct?"},
  {"\\displaystyle", "\\displaystyle correct?"},
  {"eqnarray", "Avoid eqnarray."},
  {"%$\\eqref%A", "$\\eqref --?--> \\eqref"},
  {"%${\\eqref%A", "${\\eqref --?--> \\eqref"},
  {"\\%(\\eqref%A", "\\(\\eqref --?--> \\eqref"},
  {"\\%({\\eqref%A", "\\({\\eqref --?--> \\eqref"},
  {"<<", "<< --?--> \\ll or e.g. \\langle\\kern-.2em\\langle"},
  {">>", ">> --?--> \\gg or e.g. \\rangle\\kern-.2em\\rangle"},
  {"\\in[%%\n%s]*%]", "\\in] --?--> wrap open interval in curly brackets"},
  {"\\subset[%%\n%s]*%]", "\\subset] --?--> wrap open interval in curly brackets"},
  {"\\subseteq[%%\n%s]*%]", "\\subseteq] --?--> wrap open interval in curly brackets"},
  {"%[[%%\n%s]*\\in%A", "[\\in --?--> wrap open interval in curly brackets"},
  {"%[[%%\n%s]*\\subset", "[\\subset --?--> wrap open interval in curly brackets"},
  {"\\,%s*,", "\\,, --?--> ,"},
  {"\\,%s*;", "\\,; --?--> ;"},
  {"\\,%s*%.", "\\,. --?--> ."},
  {",%s*\\cdots", ",\\cdots --?--> ,\\ldots"},
  {"begin{aligned}[%s\n~]+%[", "No [ allowed after \\begin{aligned}. Write '\\begin{aligned}{} ['"},
  {"\\section%s*{ ", "Do not use blank after \\section{"},
  {"\\subsection%s*{ ", "Do not use blank after \\subsection{"},
  {"\\subsubsection%s*{ ", "Do not use blank after \\subsubsection{"},
  {"\\paragraph%s*{ ", "Do not use blank after \\paragraph{"},
  {"\\subparagraph%s*{ ", "Do not use blank after \\subparagraph{"},
  {"||", "|| --?--> \\rvert\\lvert or \\Vert"},
  {"\\mathit", "Check use of \\mathit"},
  {"\\it[^%a]", "Avoid \\it"},
  {"\\bf[^%a]", "Avoid \\bf"},
  --
  {"In[%s\n~]+fact[^,]", "Missing comma after 'In fact'."},
  {"In[%s\n~]+particular[^,]", "Missing comma after 'In particular'."},
  {"Moreover[^,]", "Missing comma after 'Moreover'."},
  {"Finally[^,]", "Missing comma after 'Finally'."},
  {"Furthermore[^,]", "Missing comma after 'Furthermore'."},
  {"Nevertheless[^,]", "Missing comma after 'Nevertheless'."},
  {"Conversly[^,]", "Missing comma after 'Conversly'."},
  {"Consequently[^,]", "Missing comma after 'Consequently'."},
  {"equals[%s\n~]+to", "equals to --?--> 'equals' or 'is equal to'"},
  {"[Ss]imilar[%s\n~]+as", "Similar/similar as --?--> to"},
  {"[Ss]imilarly[%s\n~]+as", "Similarly/similarly as --?--> to"},
  {"[Ss]imilar[%s\n~]+arguments?[%s\n~]+as", "Similar/similar argument/s as --?--> to"},
  {"er[%s\n~]+then", "[...]er then --?--> [...]er than"},
  {"if[%s\n~]+follows", "if follows --?--> it follows"},
  {"If[%s\n~]+follows", "If follows --?--> It follows"},
  {"[iI]f[%s\n~]+and[%s\n~]+only[%s\n~]+[^i][^f]", "Probably second 'if' missing in 'if and only'"},
  {"it's", "it's --?--> 'it is' or 'its'"},
  {"It's", "It's --?--> 'It is' or 'Its'"},
  {"Let's", "Let's --?--> Let us"},
  {"we've", "we've --?--> we have"},
  {"We've", "We've --?--> We have"},
  {"n't", "n't --?--> not"},
  {"the[%s\n~]+from", "the from --?--> the form"},
  {"The[%s\n~]+from", "The from --?--> The form"},
  {"form[%s\n~]+the", "form the --?--> from the"},
  {"Form[%s\n~]+the", "Form the --?--> From the"},
  {"Leibnitz", "Leibnitz --?--> Leibniz (Gottfried Wilhelm)"},
  {"[%-–]+Schwartz", "Schwartz --?--> Schwarz (Cauchy--Schwarz)"},
  {"exits", "exits --?--> exists"},
  {"[^f]%A+[Ii]t[%s\n~]+exists", "It/it exists --?--> there exists"},
    -- N.B.: "if it exist" and "limit exists" are okay.
  {"an[%s\n~]+un", "an un --?--> a un (note: 'a unified' but 'an underlying')"},
  {"i%.e[^%.^%a]", "Final dot missing in 'i.e'"},
  {"e%.g[^%.^%a]", "Final dot missing in 'e.g'"},
  {"c%.f%.", "c.f. --> cf."},
  {"[cC]ompliment", "Compliment/compliment --?--> complement"},
  {"[Pp]receeding", "Preceeding/preceeding --?--> preceding"},
  {"[Pp]roceeded", "Proceeded/proceeded --?--> preceded/preceding"},
}
for i = 1, #pattern_note do
  F.patternsearch(texcode,pattern_note[i][1],pattern_note[i][2])
  F.add_blankline()
end

local recursivepattern_note = {
  {"Let%s*%$[^%$]-%$%s*is", "Grammar?"},
  -- TODO: Don't know how to match it with \(...\) instead of $...$.
  {"Let%s*%$[^%$]-%$%s*are", "Grammar?"},
  -- TODO: Don't know how to match it with \(...\) instead of $...$.
  {",%s*\\l?dots%s*\\?%a", "Missing comma?"},
}
for i = 1, #recursivepattern_note do
  F.recursivepatternsearch(texcode,recursivepattern_note[i][1],recursivepattern_note[i][2])
  F.add_blankline()
end

local prefix = {'equi', 'non', 'pseudo', 'quasi', 'semi', 'well'}
for i = 1, #prefix do
  F.prefixsearch(texcode,prefix[i])
  F.add_blankline()
end

local suffix = {'dimensional', 'form', 'type'}
for i = 1, #suffix do
  F.suffixsearch(texcode,suffix[i])
  F.add_blankline()
end

-- AE vs. BE
F.americanbritish(texcode)
F.add_blankline()

-- The log file is only required if the 'refcheck' package is used.
-- Since 'refcheck' could be loaded by a package, a case distinction
-- is hard and thus omitted here.
local logcode = F.read_file(input..'.log')

if logcode then
  -- Package refcheck warnings
  for line in logcode:gmatch('(.-)\n') do
    if line:match('Package refcheck Warning') then
      print("refcheck:"..line:match('Package refcheck Warning:(.-)$'))
      blankline = true
    end
  end
  F.add_blankline()
end

-- Search for uncited \bibitem's.
-- Can be solved elegantly using pl_tablex (see previous version),
-- but we want to avoid any Penlight modules here.
local cite_iterator = auxcode:gmatch('\\citation{(.-)}')
local bibitem_iterator = auxcode:gmatch('\\bibcite{(.-)}')

local cites = {}
for item in cite_iterator do
  for identifier in item:gmatch('[^,]+') do
    cites[identifier] = true
  end
end

local bibitems = {}
for item in bibitem_iterator do
  bibitems[item] = true
end

print("There are "..F.tablelength(bibitems).." \\bibitem's and "
  ..F.tablelength(cites).." \\cite's.")

-- Next, we remove all keys in cites from bibitems.
for key, _ in pairs(cites) do
  if bibitems[key] then
    cites[key] = nil
    bibitems[key] = nil
  end
end

-- Print all uncited \bibitem's.
if F.tablelength(bibitems)>0 then
  local uncited = {}
  for key, _ in pairs(bibitems) do
    uncited[#uncited + 1] = key
  end
  print("\\marginpar{Propose where to cite \\cite{"..table.concat(uncited, ', ')
    .."}. Uncited entries will be removed from the bibliography.}\n")
else
  print("All \\bibitem's are cited in the text.\n")
end

-- Print all \cite to which no \bibitem exists.
if F.tablelength(cites)>0 then
  local unmatched = {}
  for key, _ in pairs(cites) do
    unmatched[#unmatched + 1] = "\\bibitem{"..key.."}"
  end
  print("The following \\bibitem's are missing: "..table.concat(unmatched, ', ').."\n")
end

-- End of file.