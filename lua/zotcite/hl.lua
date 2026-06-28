local config = require("zotcite.config").get_config()

local M = {}

-- Line number (1-based) currently being edited in insert mode, or nil. The
-- virtual text is suppressed on this line so it isn't shown next to the raw
-- (revealed) citation key while typing.
local insert_line = nil

--- Set/clear the line whose virtual text should be suppressed (insert mode).
---@param lnum integer|nil
M.set_insert_line = function(lnum) insert_line = lnum end

---@return integer|nil
M.get_insert_line = function() return insert_line end

--- Highlight citation key and add virtual text
---@param ns integer Namespace id
---@param i integer Line
---@param s integer Column
---@param e integer End column
---@param a string
--- @param skipvt boolean|nil When true, omit the inline virtual text (used for
--- the line being edited in insert mode, so the raw key is shown without the
--- duplicated label).
local vt_citation = function(ns, i, s, e, c, a, skipvt)
    if not a then return end
    local set_m = vim.api.nvim_buf_set_extmark
    local kt = require("zotcite.config").get_key_type(vim.api.nvim_get_current_buf())
    -- `invalidate` makes a mark hide itself when the text it spans is deleted, so
    -- concealed keys and their inline virtual text don't linger after e.g. `dd`.
    if kt == "zotero" then
        a = a:gsub("%-", "_")
        set_m(
            0,
            ns,
            i - 1,
            s - 1,
            { end_col = e, hl_group = "Ignore", conceal = "", invalidate = true }
        )
        -- give the virtual-text mark a range (end_col) so it, too, can invalidate
        if not skipvt then
            set_m(0, ns, i - 1, c, {
                end_col = e,
                virt_text = { { a, "Identifier" } },
                virt_text_pos = "inline",
                invalidate = true,
            })
        end
    else
        if vim.tbl_contains({ "tex", "rnoweb", "bib" }, vim.bo.filetype) then
            set_m(
                0,
                ns,
                i - 1,
                s - 1,
                { end_col = e, hl_group = "Identifier", invalidate = true }
            )
        else
            set_m(0, ns, i - 1, s - 1, {
                end_col = s,
                hl_group = "Ignore",
                conceal = "",
                invalidate = true,
            })
            set_m(
                0,
                ns,
                i - 1,
                s,
                { end_col = e, hl_group = "Identifier", invalidate = true }
            )
        end
    end
end

local vt_citations_bib = function(lines, ns)
    local set_m = vim.api.nvim_buf_set_extmark
    local key = nil
    local citekey = nil
    local zotkey = nil
    local zlnum = 0
    local clnum = 0
    local hl = "WarningMsg"
    for k, v in pairs(lines) do
        if v:find("^@%S*{.*,%s*$") then
            key = v:match("^@%S*{(.*),%s*$")
        elseif v:find("^%s*zotkey%s*=%s{%S*},") then
            zotkey = v:match("^%s*zotkey%s*=%s{(%S*)},")
            zlnum = k
        elseif v:find("^%s*citekey%s*=%s{%S*},") then
            citekey = v:match("^%s*citekey%s*=%s{(%S*)},")
            clnum = k
        end
        if key and citekey and zotkey then
            local grd = require("zotcite.zotero").get_ref_data
            local kt =
                require("zotcite.config").get_key_type(vim.api.nvim_get_current_buf())
            local r = kt == "zotero" and grd(zotkey) or grd(citekey)
            if not r or r.zotkey ~= zotkey then
                local s, e = lines[zlnum]:find(zotkey)
                if s and e then
                    set_m(0, ns, zlnum - 1, s - 1, { end_col = e, hl_group = hl })
                end
            end
            if not r or r.citekey ~= citekey then
                local s, e = lines[clnum]:find(citekey:gsub("%-", "%%-"))
                if s and e then
                    set_m(0, ns, clnum - 1, s - 1, { end_col = e, hl_group = hl })
                end
            end
            citekey = nil
            zotkey = nil
            key = nil
        end
    end
end

local vt_citations_md = function(ac, ns, lines, iline)
    local kt = require("zotcite.config").get_key_type(vim.api.nvim_get_current_buf())
    local kp = kt == "zotero"
            and "@[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]"
        or "@[%w%-\192-\244\128-\191]+"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        local imax = #v
        while i < imax do
            local s, e = v:find(kp, i)
            if not s or not e then break end
            a = ac[v:sub(s + 1, e)]
            local ce = e
            if kt == "zotero" then
                -- Legacy support: also conceal a trailing "#"/"+" human-readable
                -- suffix (old "@<zoterokey>#<visible>" citation key format)
                local _, se = v:find("^[#+][%w_%+%-]*", e + 1)
                if se then ce = se end
            end
            vt_citation(ns, k, s, ce, s, a, k == iline)
            i = ce + 1
        end
    end
end

local vt_citations_typ = function(ac, ns, lines, iline)
    local kt = require("zotcite.config").get_key_type(vim.api.nvim_get_current_buf())
    local kp = kt == "zotero"
            and "<[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]>"
        or "<[%w%-\192-\244\128-\191]+>"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        local imax = #v
        while i < imax do
            local s, e = v:find(kp, i)
            if not s or not e then break end
            a = ac[v:sub(s + 1, e - 1)]
            vt_citation(ns, k, s, e, e, a, k == iline)
            i = e + 1
        end
    end
end

local vt_citations_tex = function(ac, ns, lines, iline)
    local kt = require("zotcite.config").get_key_type(vim.api.nvim_get_current_buf())
    local kp1 = "\\%w*cit.*{"
    local kp2 = kt == "zotero"
            and "[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]"
        or "[%w%-\192-\244\128-\191]+"
    local a = ""
    for k, v in pairs(lines) do
        local i = 1
        local imax = #v
        while i < imax do
            local s, e = v:find(kp1, i)
            if not s or not e then break end
            local j = e
            local l = v:find("%}", j)
            if not l then l = 1000 end
            while j < l do
                local s2, e2 = v:find(kp2, j)
                if not s2 or not e2 then break end
                a = ac[v:sub(s2, e2)]
                vt_citation(ns, k, s2, e2, e2, a, k == iline)
                j = e2 + 1
            end
            i = e + 1
        end
    end
end

M.citations = function()
    if not config.hl_cite_key then return end

    local ac = require("zotcite.zotero").get_all_citations()
    local ns = vim.api.nvim_create_namespace("ZCitation")
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local iline = insert_line
    if not vim.tbl_contains({ "tex", "rnoweb", "bib" }, vim.bo.filetype) then
        vt_citations_md(ac, ns, lines, iline)
    end
    if vim.bo.filetype == "typst" then
        vt_citations_typ(ac, ns, lines, iline)
    elseif vim.bo.filetype == "tex" or vim.bo.filetype == "rnoweb" then
        vt_citations_tex(ac, ns, lines, iline)
    elseif vim.bo.filetype == "bib" then
        vt_citations_bib(lines, ns)
    end
end

return M
