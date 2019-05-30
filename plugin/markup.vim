if exists("g:loaded_html_helpers") || &cp
	finish
endif

let g:loaded_html_helpers = 1
let s:save_cpo = &cpo
set cpo&vim

function! s:define_variables(settings)
	for [key, value] in items(a:settings)
		let selector = printf('g:html_helpers_%s', key)
		if !exists(selector)
			execute printf("let %s='%s'", selector, value)
		endif
	endfor
endfunction

call s:define_variables({
	\ 'multiple_line': '<C-m>'
	\ })

if exists('g:html_helpers_multiple_line')
	exec 'nnoremap <silent> '.g:html_helpers_multiple_line.
	     \' :call html_helpers#multiline("n")<CR>'
	exec 'xnoremap <silent> '.g:html_helpers_multiple_line.
	     \' :<C-u>call html_helpers#multiline("v")<CR>'
endif

let &cpo = s:save_cpo
unlet s:save_cpo
