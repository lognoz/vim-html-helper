let s:save_cpo = &cpo
set cpo&vim

let s:default_settings = {
	\ 'multiple_line': 'g<C-m>'
	\ }

function! s:init_settings(settings)
	for [key, value] in items(a:settings)
		let selector = printf('g:html_helper_%s', key)
		if !exists(selector)
			execute printf("let %s='%s'", selector, value)
		endif
	endfor
endfunction

call s:init_settings(s:default_settings)

if exists('g:html_helper_multiple_line')
	exec 'nnoremap <silent> '.g:html_helper_multiple_line.
	     \' :call html_helper#multiline("n")<CR>'
	exec 'xnoremap <silent> '.g:html_helper_multiple_line.
	     \' :<C-u>call html_helper#multiline("v")<CR>'
endif

let &cpo = s:save_cpo
unlet s:save_cpo
