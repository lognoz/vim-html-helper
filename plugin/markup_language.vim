if exists("g:loaded_markup_language") || &cp
	finish
endif

let g:loaded_markup_language = 1
let s:save_cpo = &cpo
set cpo&vim

function! s:define_variables(settings)
	for [key, value] in items(a:settings)
		let selector = printf('g:markup_language_%s', key)
		if !exists(selector)
			execute printf("let %s='%s'", selector, value)
		endif
	endfor
endfunction

call s:define_variables({
	\ 'expand': 'gS'
	\ })

if exists('g:markup_language_expand')
	exec 'nnoremap <silent> '.g:markup_language_expand.
	     \' :call markup_language#expand("n")<CR>'
	exec 'xnoremap <silent> '.g:markup_language_expand.
	     \' :<C-u>call markup_language#expand("v")<CR>'
endif

let &cpo = s:save_cpo
unlet s:save_cpo
