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

" Singleton of contextual manager instance
let s:cm = s:ContextualManager.new()
" This is the mode the user is in after s:char
let s:triggered_mode = ''
" Identation characters detected by user parameters
let s:indentation = "\t"
" List of self-closing tags
let s:self_closing_tags = [
	\ 'area', 'base', 'br', 'col', 'command', 'embed', 'hr', 'img', 'input',
	\ 'keygen', 'link', 'menuitem', 'meta', 'param', 'source', 'track', 'wbr'
	\ ]

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
	return substitute(a:string, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

" Clean lines content by calling s:trim() function
function! s:clean_lines(lines)
"	let content = ''
"	let explode = split(a:lines, "\n")
"	let selection = s:cm.selection
"	let length = (selection.end.line - selection.begin.line) + 1
"	if length != len(explode)
"		for i in range(len(explode), length)
"			let content .= "\n"
"		endfor
"	endif
"	for line in explode
"		let content .= s:trim(line) . "\n"
"	endfor
"	echo content
"	return content
	let content = ''
	for line in split(a:lines, '\n')
		let content .= s:trim(line) . "\n"
	endfor
	return content
endfunction

" Return the content by selection.
" If mode is visual, selection is getting in register * to be return
function! s:content()
	return s:clean_lines(s:triggered_mode ==# 'n' ? getline('.') : @*)
endfunction

" Return the position of the selection by triggered mode. First element is the
" line number, second element is the column number
function! s:selection()
	if s:triggered_mode ==# 'v'
		return s:region("'<", "'>")
	else
		return {
			\ 'begin': { 'line': line('.'), 'col': 1 },
			\ 'end': { 'line': line('.'), 'col': col("$") }
			\ }
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

" Add visual selection by triggered mode
" If it's normal mode, current line will be selected
function! s:select_in_visual_mode()
	if s:triggered_mode ==# 'v'
		execute "normal! gv"
	else
		execute "normal! V"
	endif
endfunction

" Get indentation from document setting
function! s:get_document_indentation()
	let sw = exists('*shiftwidth') ? shiftwidth() : &l:shiftwidth
	let indent = (&l:expandtab || &l:tabstop !=# sw) ? repeat(' ', sw) : "\t"
	return indent
endfunction

" Add tab before a string content. In function, s:indentation variable is
" referring document indentation character type
function! s:fix_indent(string, indent)
	return repeat(s:indentation, a:indent).a:string
endfunction

" Replace the selection by the parsed content
function! s:replace_selection(content)
	call s:select_in_visual_mode()
	execute "normal! c"
	call append(line('.'), a:content)
	execute "normal! dd"
endfunction

" Get indentation from line number
function! s:extract_indent(line)
	return matchstr(getline(a:line), '^\s\+')
endfunction

function! s:extract_line(selection, content)
	let lines = split(a:content, "\n")
	let length = [len(lines), a:selection.end.line - a:selection.begin.line + 1]
	if length[0] < length[1]
		for i in range(length[0], length[1] - 1)
			let lines = [''] + lines
		endfor
	endif
	return lines
endfunction

" Extracting lines content and indentation
function! s:lines(selection, content)
	let parameters = []
	let line = a:selection['begin']['line']
	for content in s:extract_line(a:selection, a:content)
		call add(parameters, {
			\ 'content': content,
			\ 'indent': s:extract_indent(line)
			\ })
		let line += 1
	endfor
	return parameters
endfunction

" Verify if select to start
function! s:select_to_start(selection)
	return a:selection['begin']['col'] > 1
endfunction

" Verify if select to end
function! s:select_to_end(selection)
	return a:selection['end']['col'] < len(getline(a:selection['end']['line'])) + 1
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
			if has_key(unclose, name[1:])
				let tags[name[1:]]['close'] = cpt-1
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

function! s:parse_lines(param, tags)
	let lines = []
	let position = 0
	let indent = 0

	if len(a:tags) == 0
		return [join([a:param.indent, a:param.content], '')]
	endif

	for tag in a:tags
		if tag.position > position
			let part = strpart(a:param.content, position, tag.position - position)
			call add(lines, join([a:param.indent, s:fix_indent(part, indent)], ''))
		endif

		if tag.name[0] == '/'
			let indent = indent - 1
		endif

		let position = tag.position + tag.length
		let part = strpart(a:param.content, tag.position, tag.length)
		call add(lines, join([a:param.indent, s:fix_indent(part, indent)], ''))

		if tag.name[0] != '/' && index(s:self_closing_tags, tag.name) == -1
			let indent = indent + 1
		endif
	endfor

	if (len(a:param.content) > position)
		let part = strpart(a:param.content, position, len(a:param.content))
		call add(lines, join([a:param.indent, s:fix_indent(part, indent)], ''))
	endif

	return lines
endfunction

"===============================================================================
" Public functions
"===============================================================================

" Set triggered mode and call function html_helper#apply with feedkeys
" At the end contextual manager is reseted
function! html_helper#multiline(mode)
	let s:triggered_mode = a:mode
	let s:indentation = s:get_document_indentation()
	call feedkeys("\<Plug>(html-helper-apply-multiline)")
	call s:cm.reset()
endfunction

" Transform line to multiple line based on tags
" This function is called by feedkeys plugin html-helper-apply-multiline
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

	" Extracting tags from s:lines() results and parse lines by tags found
	" Turn variable tags_exist to true if tags was found
	let lines = []
	let tags_exist = 0
	for parameters in s:lines(s:cm.selection, s:cm.content)
		" Extract tags from selection content
		" If none have been found [] will be returns
		let tags = s:extract_tags(parameters['content'])
		let lines += s:parse_lines(parameters, tags)
		if tags != []
			let tags_exist = 1
		endif
	endfor

	if s:select_to_start(s:cm.selection)
		let position = s:cm.selection.begin
		let content = strpart(getline(position.line), 0, position.col - 1)
		if s:trim(content) != ''
			let lines = [content] + lines
		endif
	endif

	if s:select_to_end(s:cm.selection)
		let position = s:cm.selection.end
		let content = strpart(getline(position.line), position.col)
		if s:trim(content) != ''
			let content = s:extract_indent(position.line) . content
			let lines = lines + [content]
		endif
	endif

	" Output warning message if no tags have been found
	" Stop the process of the function by returning 0
	if tags_exist == 0
		return s:display_warning("No html tag found")
	endif

	call s:replace_selection(lines)
endfunction
