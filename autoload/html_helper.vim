"===============================================================================
" Internal Mappings
"===============================================================================

nnoremap <silent> <Plug>(html-helper-apply-multiline) :call html_helper#apply()<CR>
xnoremap <silent> <Plug>(html-helper-apply-multiline) :<C-u>call html_helper#apply()<CR>

"===============================================================================
" Contextual class
"===============================================================================

let s:ContextualManager = {}

" Constructor
function! s:ContextualManager.new()
	let obj = copy(self)
	" List of tags we're managing
	let obj.tags = []
	" List of selection positions
	let obj.selection = []
	" Selection content
	let obj.content = ''
	return obj
endfunction

" Clear all configurations
function! s:ContextualManager.reset() dict
	let self.content = ''
	let self.selection = []
	let self.tags = []
endfunction

" Define class attribute
function! s:ContextualManager.define(param, value) dict
	let self[a:param] = a:value
endfunction

" Debug helpers
function! s:ContextualManager.debug() dict
	echom 'position [line, column]:'
	echom '  start = [' . self.selection[0][0] . ', ' . self.selection[0][1] . ']'
	echom '  end = [' . self.selection[1][0] . ', ' . self.selection[1][1] . ']'
	echom 'tags [position, length]:'
	for tag in self.tags
		echom '  <' . tag.name . '> = [' . tag.position . ', ' . tag.length . ']'
	endfor
endfunction

"===============================================================================
" Variables
"===============================================================================

" This is the mode the user is in after s:char
let s:triggered_mode = ''
" Singleton of contextual manager instance
let s:cm = s:ContextualManager.new()

"===============================================================================
" Utility functions
"===============================================================================

" Return the position of the input marker as array. First element is the line
" number, second element is the column number
function! s:pos(mark)
	return [line(a:mark), col(a:mark)-1]
endfunction

" Return the position of the input marker as array. First element is the start
" marker position, second last marker position
function! s:region(start_mark, end_mark)
	return [s:pos(a:start_mark), s:pos(a:end_mark)]
endfunction

" Return the content by selection.
" If mode is visual, selection is copying in register "a to be return
function! s:content()
	if s:triggered_mode ==# 'n'
		return getline('.')
	else
		let a_save = @a
		normal! gv"ay
		return @a
	endif
endfunction

" Return the position of the selection by triggered mode. First element is the
" line number, second element is the column number
function! s:selection()
	if s:triggered_mode ==# 'n'
		let selection = s:region(".", ".")
		let selection[0][1] = 0
		let selection[1][1] = len(getline("."))
		return selection
	else
		return s:region("'<", "'>")
	endif
endfunction

" Output error message
function! s:display_error(feedback)
	echohl ErrorMsg | echo a:feedback | echohl None
endfunction

" Output warning message
function! s:display_warning(feedback)
	echohl WarningMsg | echo a:feedback | echohl None
endfunction

function! s:extract_tags(content)
	let cpt = 0
	let tags = []
	let unclose = {}
	while 1
		let cpt += 1
		let match = matchstr(a:content, '<[^<>]*>', 0, cpt)
		if match == ''
			break
		endif
		let name = matchstr(match, '<\zs/\?\%([[:alpha:]_:]\|[^\x00-\x7F]\)\%([-._:[:alnum:]]\|[^\x00-\x7F]\)*')
		let position = match(a:content, '<[^<>]*>', 0, cpt)
		if name[0] == '/'
			let key = name[1:]
			if has_key(unclose, name[1:])
				let tags[key]['close'] = cpt-1
			endif
		else
			let unclose[name] = {
				\ 'position': position,
				\ 'cpt': cpt-1
				\ }
		endif
		call add(tags, {
			\ 'name': name,
			\ 'position': position,
			\ 'length': len(match)
			\ })
	endwhile
	return tags
endfunction

function! s:parse_content()
	let content = s:cm.content
	let lines = []
	let position = 0
	let indent = 0
	for tag in s:cm.tags
		if tag['position'] > position
			let string = strpart(content, position, tag['position'] - position)
			for line in split(string, '\n')
				call add(lines, line)
			endfor
		endif
		let position = tag['position'] + tag['length']
		call add(lines, strpart(content, tag['position'], tag['length']))
	endfor
	if (len(content) > position)
		let string = strpart(content, position, len(content))
		for line in split(string, '\n')
			call add(lines, line)
		endfor
	endif
	return lines
endfunction

function! s:select_in_visual_mode()
	if s:triggered_mode ==# 'v'
		normal! gv
	else
		normal! V
	endif
endfunction

"===============================================================================
" Public functions
"===============================================================================

" Set triggered mode and call function html_helper#apply with feedkeys
" At the end contextual manager is reseted
function! html_helper#multiline(mode)
	let s:triggered_mode = a:mode
	call feedkeys("\<Plug>(html-helper-apply-multiline)")
	call s:cm.reset()
endfunction

function! html_helper#apply()
	" Disabled visual block mode and output error message in this case
	" Stop the process of the function by returning 0
	if s:triggered_mode ==# 'v'
		let visual = visualmode()
		if visual != 'v' && visual != 'V'
			return s:display_error("Visual block can't be use as selector")
		endif
	endif

	" Define selection and content by triggered mode to contextual manager
	" 'content': s:content() function return selection content
	" 'selection': s:selection() function will return an array of positions
	" [start_line, start_column], [end_line, end_column]
	call s:cm.define('selection', s:selection())
	call s:cm.define('content', s:content())

	" Verify selection is empty lines
	if s:cm.selection[0] == s:cm.selection[1]
		return s:display_warning("No match found")
	endif

	call s:cm.debug()

"	" Getting tags
"	let tags = s:extract_tags(s:cm.content)
"	call s:cm.define('tags', tags)
"	if len(tags) == 0
"		return s:display_warning("No html tag found")
"	endif
"
"	" Parse content
"	let content = s:parse_content()
"	call s:select_in_visual_mode()
"	normal! c
"	call append(line('.'), content)
"	normal! dd
endfunction
