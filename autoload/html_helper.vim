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
	return {
		\ 'line': line(a:mark),
		\ 'col': col(a:mark)
		\ }
endfunction

" Return the position of the input marker as array. First element is the start
" marker position, second last marker position
function! s:region(start_mark, end_mark)
	return {
		\ 'begin': s:pos(a:start_mark),
		\ 'end': s:pos(a:end_mark)
		\ }
endfunction

" Strip whitespace (or other characters) from the beginning and end of a string
function! s:trim(string)
	let final = ''
	for line in split(a:string, '\n')
		let final .= substitute(line, '^\s*\(.\{-}\)\s*$', '\1', '') . "\n"
	endfor
	return final
endfunction

" Return the content by selection.
" If mode is visual, selection is copying in register "a to be return
function! s:content()
	if s:triggered_mode ==# 'n'
		let string = getline('.')
	else
		let a_save = @a
		normal! gv"ay
		let string = @a
	endif
	return s:trim(string)
endfunction

" Return the position of the selection by triggered mode. First element is the
" line number, second element is the column number
function! s:selection()
	if s:triggered_mode ==# 'n'
		let begin = { 'line': line('.'), 'col': 1 }
		let end = { 'line': line('.'), 'col': col("$") }
		return { 'begin': begin, 'end': end }
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

" Extracting tags from string
" Return an array of tags found
" If no one was found [] will be return
function! s:extract_tags(content)
	" Counter that will be use to matchstr tags
	let cpt = 0
	" List of tags found
	let tags = []
	" List of tags unclosed
	let unclose = {}
	" Loop until we can't found new match tag
	" If match is empty the loop will be breaks
	while 1
		let cpt += 1
		" Match tags in the content
		let match = matchstr(a:content, '<[^<>]*>', 0, cpt)
		if match == ''
			break
		endif
		" Remove all attributes in match found
		" <p class="a"> will be p and </p> will be /p
		let name = matchstr(match, '<\zs/\?\%([[:alpha:]_:]\|[^\x00-\x7F]\)\%([-._:[:alnum:]]\|[^\x00-\x7F]\)*')
		let position = match(a:content, '<[^<>]*>', 0, cpt)
		" If first character egale backslash a condition is executed to verify
		" if this tags has parent in unclose variable. If key exist the close
		" tag will be added to the parent
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
		" Add information about tag found
		" name: name of the tag that have been found (p or /p)
		" position: position start of the match
		" length: length of the match
		call add(tags, {
			\ 'name': name,
			\ 'position': position,
			\ 'length': len(match)
			\ })
	endwhile
	return tags
endfunction

function! s:parse_content(content, tags, selection)
	let lines = []
	let position = 0

	" If line is not fully selected
	if a:selection['begin']['col'] > 1
		let string = strpart(getline(a:selection['begin']['line']), 0, a:selection['begin']['col'] - 1)
		let string = substitute(string, '^\s*\(.\{-}\)\s*$', '\1', '')
		if string != ''
			call add(lines, string)
		endif
	endif

	for tag in a:tags
		if tag['position'] > position
			let string = strpart(a:content, position, tag['position'] - position)
			for line in split(string, '\n')
				call add(lines, line)
			endfor
		endif
		let position = tag['position'] + tag['length']
		call add(lines, strpart(a:content, tag['position'], tag['length']))
	endfor

	" If line is not fully selected
	if a:selection['end']['col'] < len(getline(a:selection['end']['line'])) + 1
		let string = strpart(getline(a:selection['end']['line']), a:selection['end']['col'])
		let string = substitute(string, '^\s*\(.\{-}\)\s*$', '\1', '')
		call add(lines, string)
	endif

	if (len(a:content) > position)
		let string = strpart(a:content, position, len(a:content))
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
	" content: s:content() function return selection content
	" selection: s:selection() function will return an array of positions
	call s:cm.define('selection', s:selection())
	call s:cm.define('content', s:content())

	" Output warning message if selection content is empty after triming
	" Stop the process of the function by returning 0
 	if substitute(s:cm.content, '\t\n\+$', '', '') == ''
		return s:display_warning("No match found")
 	endif

	" Extract tags from selection content
	" If none have been found [] will be returns
	" Else a directory will be store for every tag
	call s:cm.define('tags', s:extract_tags(s:cm.content))

	" Output warning message if no tags have been found
	" Stop the process of the function by returning 0
	if len(s:cm.tags) == 0
		return s:display_warning("No html tag found")
	endif

	"call s:cm.debug()

	" Parse content
	let content = s:parse_content(s:cm.content, s:cm.tags, s:cm.selection)
	call s:select_in_visual_mode()
	normal! c
	call append(line('.'), content)
	normal! dd
endfunction
