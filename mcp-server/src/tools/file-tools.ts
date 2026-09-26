/**
 * File operation tools for Godot MCP Server
 * MVP tools: list_dir, read_file, search_project, create_script
 */

import type { ToolDefinition } from '../types.js';

export const fileTools: ToolDefinition[] = [
  {
    name: 'list_dir',
    description: 'List files and folders under a Godot project path (e.g., res://). Returns arrays of files and folders in the specified directory.',
    inputSchema: {
      type: 'object',
      properties: {
        root: {
          type: 'string',
          description: 'Starting path like res://addons/ai_assistant or res://'
        }
      },
      required: ['root']
    }
  },
  {
    name: 'read_file',
    description: 'Read a text file from the Godot project, optionally a specific line range. Useful for reading GDScript files, scene files, or any text-based content.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'res:// path to the file (e.g., res://scripts/player.gd)'
        },
        start_line: {
          type: 'number',
          description: '1-based inclusive start line (optional)'
        },
        end_line: {
          type: 'number',
          description: 'Inclusive end line; 0 or missing means to end of file (optional)'
        },
        preview: {
          type: 'boolean',
          description: 'Return a numbered head+tail excerpt (default 40 head / 10 tail lines) instead of the byte-budgeted full read. Good for orienting in large files.'
        },
        preview_head: {
          type: 'number',
          description: 'Head lines in preview mode (default 40)'
        },
        preview_tail: {
          type: 'number',
          description: 'Tail lines in preview mode (default 10)'
        },
        redact_secrets: {
          type: 'boolean',
          description: 'Best-effort scrub of api keys/tokens/passwords in the returned content (default true)'
        }
      },
      required: ['path']
    }
  },
  {
    name: 'search_project',
    description: 'Search the Godot project for a substring and return file hits with line numbers. Useful for finding usages of functions, variables, or any text pattern.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Case-insensitive substring to find'
        },
        glob: {
          type: 'string',
          description: 'Optional glob filter like **/*.gd to search only GDScript files'
        }
      },
      required: ['query']
    }
  },
  {
    name: 'create_script',
    description: 'Create a NEW GDScript file (.gd) that does not exist yet. STRICTLY for .gd files — non-.gd extensions (.json, .gdignore, .md, etc.) are rejected with a pointer at write_file. A missing extension is auto-completed to .gd. Use edit_script for changes to an existing file. Use classdb_query to verify unfamiliar Godot class methods. After creating a script, consider run_scene and get_errors to verify it parses and behaves.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Script file path (res://scripts/player.gd) - must not exist yet'
        },
        content: {
          type: 'string',
          description: 'Full GDScript content to write to the file'
        }
      },
      required: ['path', 'content']
    }
  },
  {
    name: 'find_files_by_name',
    description: 'Find files by exact filename or substring across the project (or a subdirectory). Skips hidden dirs like .git/.godot.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Filename or substring (case-insensitive)' },
        root: { type: 'string', description: 'Directory scope; defaults to res://' },
        exact: { type: 'boolean', description: 'Require an exact filename match (default false)' },
        max_results: { type: 'number', description: 'Cap on matches (default 50)' }
      },
      required: ['name']
    }
  },
  {
    name: 'get_file_outline',
    description: 'Top-level declarations of a .gd file (funcs, vars, consts, signals, enums, classes) with line numbers and func/class end-line spans. Cheaper than reading the whole file; pair with read_file start_line/end_line to fetch bodies.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Path to the .gd file' },
        include_locals: { type: 'boolean', description: 'Also list declarations inside function bodies (default false)' }
      },
      required: ['path']
    }
  }
];
