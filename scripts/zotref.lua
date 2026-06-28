--[[
zotref.lua — Pandoc Lua filter for zotcite's legacy citation-key format.

Background: before the Typst/LaTeX refactor, zotcite used citation keys of the
form "@<8-char-zotero-key>#<human-readable-suffix>" (e.g. @BGKCHUUS#los) and a
Python filter (python3/zotref.py, function WalkClean) stripped the "#..." suffix
before citeproc resolved the key against the generated .bib. That Python filter
was removed when the bib generator moved into Lua.

This filter restores that behaviour for documents that still use the legacy
format: it strips a trailing "#..."/"+..." suffix from every citation id so the
id matches the zotero-key-based entry written into the .bib by bib.lua. A "-"
suffix is deliberately left untouched, since template/better-bibtex citation
keys may legitimately contain hyphens.

Usage (Markdown/Quarto, run BEFORE --citeproc):
  pandoc --lua-filter=/path/to/zotcite/scripts/zotref.lua --citeproc in.md -o out.pdf
or in a Quarto YAML header:
  filters:
    - /path/to/zotcite/scripts/zotref.lua
    - citeproc
--]]

function Cite(el)
    for _, c in ipairs(el.citations) do
        c.id = c.id:gsub("[#+].*", "")
    end
    return el
end
