/**
 * Editor viewport capture tools.
 *
 * The GD-side tool returns { image_b64, mime, ... }; index.ts unwraps
 * image_b64 into native MCP image content so vision-capable clients see
 * the screenshot directly.
 */
import type { ToolDefinition } from '../types.js';

export const captureTools: ToolDefinition[] = [
  {
    name: 'capture_editor_screenshot',
    description: 'Capture the Godot EDITOR viewport (not the running game) and return it as native MCP image content, downscaled to at most 1280px on the long side. Use to eyeball the scene currently open in the editor.',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  },
];
