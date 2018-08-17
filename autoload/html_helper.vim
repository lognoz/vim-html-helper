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
let s:indentation = "\n"
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
function! s:trim(...)
	let string = ''
	for line in split(a:1, '\n')
		let string .= substitute(line, '^\s*\(.\{-}\)\s*$', '\1', '') . "\n"
	endfor
	return string
endfunction

" Return the content by selection.
" If mode is visual, selection is getting in register * to be return
function! s:content()
	if s:triggered_mode ==# 'n'
		let string = getline('.')
	else
		let string = @*
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

function! s:extract_indent(line)
	return matchstr(getline(a:line), '^\s\+')
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

function! s:lines(selection, content)
	let lines = []
	let line = a:selection['begin']['line']
	for content in split(a:content, "\n")
		let parameter = {}
		let parameter['content'] = content
		let parameter['indent'] = s:extract_indent(line)
		call add(lines, parameter)
		let line += 1
	endfor
	return lines
endfunction

function! s:select_to_start(selection)
	return a:selection['begin']['col'] > 1
endfunction

function! s:select_to_end(selection)
	return a:selection['end']['col'] < len(getline(a:selection['end']['line'])) + 1
endfunction

function! s:parse_content(content, tags, selection)
	let lines = []
	let position = 0
	let indent = 0

	if s:select_to_start(a:selection)
		let begin = a:selection['begin']
		let string = strpart(getline(begin['line']), 0, begin['col'] - 1)
		if string != ''
			call add(lines, string)
		endif
	endif

	for tag in a:tags
		if tag['position'] > position
			let string = strpart(a:content, position, tag['position'] - position)
			for line in split(string, '\n')
				call add(lines, s:fix_indent(line, indent))
			endfor
		endif

		if tag['name'][0] == '/'
			let indent = indent - 1
		endif

		let position = tag['position'] + tag['length']
		call add(lines, s:fix_indent(strpart(a:content, tag['position'], tag['length']), indent))

		if tag['name'][0] != '/' && index(s:self_closing_tags, tag['name']) == -1
			let indent = indent + 1
		endif
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

function! s:parse_lines(param, tags)
	let lines = []
	let position = 0
	let indent = 0

	if len(a:tags) == 0
		call add(lines, join([a:param.indent, a:param.content], ''))
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
	call s:cm.define('lines', s:lines(s:cm.selection, s:cm.content))

	" Output warning message if selection content is empty after triming
	" Stop the process of the function by returning 0
	if substitute(s:cm.content, '\t\n\+$', '', '') == ''
		return s:display_warning("No match found")
	endif

	let lines = []
	let tags_exist = 0
	for parameters in s:lines(s:cm.selection, s:cm.content)
		let tags = s:extract_tags(parameters['content'])
		let lines += s:parse_lines(parameters, tags)
		if tags != []
			let tags_exist = 1
		endif
	endfor

	" Output warning message if no tags have been found
	" Stop the process of the function by returning 0
	if tags_exist == 0
		return s:display_warning("No html tag found")
	endif

	call s:replace_selection(lines)

	" Extract tags from selection content
	" If none have been found [] will be returns
	" Else a directory will be store for every tag
	"call s:cm.define('tags', s:extract_tags(s:cm.content))


	" Parse content
	"let lines = s:parse_content(s:cm.content, s:cm.tags, s:cm.selection)
	"let lines = s:parse_lines()
endfunction
