let s:save_cpo = &cpo
set cpo&vim

nnoremap <silent> gm :call html_helper#multiline('n')<CR>
xnoremap <silent> gm :<C-u>call html_helper#multiline('v')<CR>

let &cpo = s:save_cpo
unlet s:save_cpo
