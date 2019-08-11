" vim:foldmethod=marker:fen:sw=4:sts=4
scriptencoding utf-8


" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

function! s:SID() abort "{{{
    return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction "}}}
let s:SID_PREFIX = s:SID()
delfunc s:SID



" Variables
"
" The handlers for all keys in each mode.
" used by eskk#complete#eskkcomplete().
let s:MODE_FUNC_TABLE = {}
" The previously completed candidates in each mode.
let s:completed_candidates = {}
" The previously completed dictionary word items.
let s:completed_dict_items = []



" Complete Function
function! eskk#complete#eskkcomplete(findstart, base) abort "{{{
    if !eskk#is_enabled()
        return s:skip_complete(a:findstart)
    endif

    call eskk#logger#debug('eskk#complete#eskkcomplete(): '
                \                    . 'a:findstart = ' . a:findstart
                \                    . ', a:base = ' . string(a:base))

    " Complete Function should not throw exception.
    try
        return s:eskkcomplete(a:findstart, a:base)
    catch
        redraw
        call eskk#logger#log_exception('s:eskkcomplete()')

        return s:skip_complete(a:findstart)
    endtry
endfunction "}}}
function! s:eskkcomplete(findstart, base) abort "{{{
    if a:findstart
        if !eskk#complete#can_find_start()
            return (v:version > 703 || v:version == 703 && has('patch519')) ?
                        \ -3 : -1
        endif
        let begin_col = eskk#get_preedit().get_begin_col()
        if begin_col >= 0 && empty(eskk#complete#do_complete(
                    \         eskk#get_preedit().get_old_str()))
            " Skip completion.
            let begin_col = -1
        endif
        if begin_col <=# 0
            return (v:version > 703 || v:version == 703 && has('patch519')) ?
                        \ -3 : -1
        endif
        return begin_col - 1
    endif

    return eskk#complete#do_complete(a:base)
endfunction "}}}
function! eskk#complete#can_find_start() abort "{{{
    if !eskk#is_enabled()
        return 0
    endif

    if !has_key(s:MODE_FUNC_TABLE, eskk#get_mode())
        return 0
    endif

    let preedit = eskk#get_preedit()
    let col = preedit.get_begin_col()
    if col <=# 0
        return 0
    endif

    let buf_str = preedit.get_buf_str(preedit.get_henkan_phase())
    if preedit.get_henkan_phase() ==# g:eskk#preedit#PHASE_HENKAN
                \   && buf_str.empty()
        return 0
    endif

    return 1
endfunction "}}}
function! eskk#complete#do_complete(base) abort "{{{
    let mode = eskk#get_mode()
    if has_key(s:MODE_FUNC_TABLE, mode)
        return s:MODE_FUNC_TABLE[mode](a:base)
    else
        return s:skip_complete()
    endif
endfunction "}}}

function! eskk#complete#_reset_completed_candidates() abort "{{{
    let s:completed_candidates = {}
    let s:completed_dict_items = []
endfunction "}}}
function! eskk#complete#_add_completed_candidates() abort "{{{
    if empty(v:completed_item)
        return
    endif

    let items = filter(copy(s:completed_dict_items),
                \ 'v:val.input ==# v:completed_item.word')
    if empty(items)
        return
    endif

    " Move self to the first.
    let dict = eskk#get_skk_dict()
    call dict.forget_word(items[0])
    call dict.remember_word(items[0])
    call eskk#complete#_reset_completed_candidates()
endfunction "}}}
function! eskk#complete#has_candidates(base) "{{{
    try
        return !empty(eskk#complete#do_complete(a:base))
    catch
        return 0
    endtry
endfunction "}}}
function! s:skip_complete(...) abort "{{{
    let findstart = get(a:000, 0, 0)
    if findstart
        return (v:version > 703 || v:version == 703 && has('patch519')) ?
                    \ -3 : -1
    else
        return s:get_completed_candidates(
                    \   eskk#get_preedit().get_display_str(1, 0),
                    \   []
                    \)
    endif
endfunction "}}}
function! s:has_completed_candidates(display_str) abort "{{{
    let NOTFOUND = {}
    return s:get_completed_candidates(a:display_str, NOTFOUND) isnot NOTFOUND
endfunction "}}}
function! s:get_completed_candidates(display_str, else) abort "{{{
    let mode = eskk#get_mode()
    if !has_key(s:completed_candidates, mode)
        return a:else
    endif
    return get(
                \   s:completed_candidates[mode],
                \   a:display_str,
                \   a:else
                \)
endfunction "}}}
function! s:set_completed_candidates(display_str, candidates, dict_items) abort "{{{
    let s:completed_dict_items = a:dict_items
    if a:display_str ==# ''    " empty string cannot be a key of dictionary.
        return
    endif
    let mode = eskk#get_mode()
    if !has_key(s:completed_candidates, mode)
        let s:completed_candidates[mode] = {}
    endif
    let s:completed_candidates[mode][a:display_str] = a:candidates
endfunction "}}}

" s:MODE_FUNC_TABLE
function! s:MODE_FUNC_TABLE.hira(base) abort "{{{
    " Do not complete while inputting rom string.
    if a:base =~# '\a$'
        return s:skip_complete()
    endif
    let mb_str = eskk#get_preedit().get_buf_str(
                \   g:eskk#preedit#PHASE_HENKAN
                \).rom_pairs.get_filter()
    let length = eskk#util#mb_strlen(mb_str)
    if length < g:eskk#start_completion_length
        return s:skip_complete()
    endif

    return s:complete(eskk#get_mode(), a:base)
endfunction "}}}
let s:MODE_FUNC_TABLE.kata = s:MODE_FUNC_TABLE.hira
function! s:MODE_FUNC_TABLE.ascii(base) abort "{{{
    " ASCII mode.
    return s:complete("ascii", a:base)
endfunction "}}}
function! s:MODE_FUNC_TABLE.abbrev(base) abort "{{{
    " abbrev mode.
    return s:complete("abbrev", a:base)
endfunction "}}}

function! s:complete(mode, ...) abort "{{{
    let preedit = eskk#get_preedit()
    let disp = preedit.get_display_str(1, 0)    " with marker, no rom_str.
    if s:has_completed_candidates(disp)
        return s:skip_complete()
    endif

    " Get candidates.
    let list = []
    let dict = eskk#get_skk_dict()

    if g:eskk#kata_convert_to_hira_at_completion
                \   && a:mode ==# 'kata'
        let [henkan_buf_str, okuri_buf_str] =
                    \   preedit.convert_rom_all(
                    \       [
                    \           g:eskk#preedit#PHASE_HENKAN,
                    \           g:eskk#preedit#PHASE_OKURI,
                    \       ],
                    \       eskk#get_mode_table('hira')
                    \   )
    else
        let henkan_buf_str = preedit.get_buf_str(
                    \   g:eskk#preedit#PHASE_HENKAN
                    \)
        let okuri_buf_str = preedit.get_buf_str(
                    \   g:eskk#preedit#PHASE_OKURI
                    \)
    endif
    let key       = henkan_buf_str.rom_pairs.get_filter()
    let okuri     = okuri_buf_str.rom_pairs.get_filter()
    let okuri_rom = okuri_buf_str.rom_pairs.get_rom()

    let candidates = dict.search_all_candidates(key, okuri, okuri_rom)
    if empty(candidates)
        return s:skip_complete()
    endif

    let do_list_okuri_candidates =
                \   preedit.get_henkan_phase() ==# g:eskk#preedit#PHASE_OKURI
    for c in candidates
        if do_list_okuri_candidates
            if c.okuri_rom_first !=# ''
                call add(list, {
                            \   'word': c.input,
                            \   'abbr': c.input
                            \           . (get(c, 'annotation', '') !=# '' ?
                            \               '; ' . c.annotation : ''),
                            \   'menu': 'kanji:okuri'
                            \})
            endif
            continue
        endif

        call add(list, {
                    \   'word': c.input,
                    \   'abbr': c.input
                    \           . (get(c, 'annotation', '') !=# '' ?
                    \               '; ' . c.annotation : ''),
                    \   'menu': 'kanji'
                    \})
    endfor

    call s:set_completed_candidates(disp, list, candidates)

    return list
endfunction "}}}


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
