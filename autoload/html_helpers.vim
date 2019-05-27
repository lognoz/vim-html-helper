"===============================================================================
" Internal Mappings
"===============================================================================

nnoremap <silent> <Plug>(html-helpers-apply-multiline) :call html_helpers#apply()<CR>
xnoremap <silent> <Plug>(html-helpers-apply-multiline) :<C-u>call html_helpers#apply()<CR>

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

" Extracting lines from content. A bug appends with empty lines in first selection
" position if split is use directly. This function calculate the difference
" between split length and selection length to fix this problem.
function! s:extract_line(selection, content)
	let lines = split(a:content, "\n")
	let length = a:selection.end.line - a:selection.begin.line + 1
	if length != len(lines)
		while length >= len(lines)
			let lines = [''] + lines
			let length -= 1
		endwhile
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

" Return content without server tags like <?= ?>, <?php ?>, <% %>
function! s:strip_server_tags(content)
	let regex = '<?=\=\%(php\)\=.\{-}?>\|<%=\=.\+%>'
	let content = a:content
	while 1
		let match = matchstr(content, regex)
		if match == ''
			break
		endif
		let content = substitute(content, regex, repeat('#', len(match)), '')
	endwhile
	return content
endfunction

" Extracting tags from string
" Return an array of tags found
" If no one was found [] will be return
function! s:extract_tags(content)
	" Content without server tags
	let content = s:strip_server_tags(a:content)
	" Counter that will be use to matchstr tags
	let cpt = 0
	" List of tags found
	let tags = []
	" Loop until we can't found new match tag
	" If match is empty the loop will be breaks
	while 1
		let cpt += 1
		" Match tags in the content
		let match = matchstr(content, '<[^<>]*>', 0, cpt)
		if match == ''
			break
		endif
		" Remove all attributes in match found
		" <p class="a"> will be p and </p> will be /p
		let name = matchstr(match, '<\zs/\?\%([[:alpha:]_:]\|[^\x00-\x7F]\)\%([-._:[:alnum:]]\|[^\x00-\x7F]\)*')
		let position = match(content, '<[^<>]*>', 0, cpt)
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

" Get content with two positions and fix the indentation
function! s:parse_line(param, indent, position)
	let part = s:trim(strpart(a:param.content, a:position[0], a:position[1]))
	return join([a:param.indent, s:fix_indent(part, a:indent)], '')
endfunction

" Parse lines with its tags find in it. Each tags will be added
" on lines array and will be formated with its lines indentation.
function! s:parse_content(param, tags)
	" Lines formated
	let lines = []
	" Position of lines analysed
	let position = 0
	" Current indentation
	let indent = 0

	" If no tag was found the line will stay the same
	if len(a:tags) == 0
		return [join([a:param.indent, a:param.content], '')]
	endif
	" Parse tags stored in argument variable a:tags
	for tag in a:tags
		" Append content before current tags
		if tag.position > position
			let content = s:parse_line(a:param, indent, [position, tag.position - position])
			if s:trim(content) != ''
				call add(lines, content)
			endif
		endif
		" Decreases the indentation if it's an close tags
		if tag.name[0] == '/'
			let indent = indent - 1
		endif
		" Update the current position analysis
		let position = tag.position + tag.length
		" Append tag content
		call add(lines, s:parse_line(a:param, indent, [tag.position, tag.length]))
		" Increase the indentation if it's not a self closing tag
		if tag.name[0] != '/' && index(s:self_closing_tags, tag.name) == -1
			let indent = indent + 1
		endif
	endfor
	" Append content after last tag
	if (len(a:param.content) > position)
		call add(lines, s:parse_line(a:param, indent, [position, len(a:param.content)]))
	endif

	return lines
endfunction

"===============================================================================
" Public functions
"===============================================================================

" Set triggered mode and call function html_helpers#apply with feedkeys
" At the end contextual manager is reseted
function! html_helpers#multiline(mode)
	let s:triggered_mode = a:mode
	let s:indentation = s:get_document_indentation()
	call feedkeys("\<Plug>(html-helpers-apply-multiline)")
	call s:cm.reset()
endfunction

" Transform line to multiple line based on tags
" This function is called by feedkeys plugin html-helpers-apply-multiline
function! html_helpers#apply()
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
		" Extract tags from selection content and
		" If none have been found [] will be returns
		let tags = s:extract_tags(parameters['content'])
		let lines += s:parse_content(parameters, tags)
		if tags != []
			let tags_exist = 1
		endif
	endfor

	" Detect if the selection is from the start
	if s:select_to_start(s:cm.selection)
		let position = s:cm.selection.begin
		let content = strpart(getline(position.line), 0, position.col - 1)
		if s:trim(content) != ''
			let lines = [content] + lines
		endif
	endif

	" Detect if the selection is from the end
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

	" Replace the selection by the parsed content
	call s:replace_selection(lines)
endfunction
