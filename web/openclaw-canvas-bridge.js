/**
 * OpenClaw Canvas Bridge - JavaScript Helper for Canvas HTML Pages
 * 
 * Include this script in your canvas HTML to communicate with ClawReach:
 * <script src="openclaw-canvas-bridge.js"></script>
 * 
 * Then use the global `openclawCanvas` object to interact with the app.
 */

(function() {
  'use strict';

  // Canvas API
  const openclawCanvas = {
    /**
     * Send a message to the ClawReach app
     */
    sendMessage(type, data = {}) {
      const message = {
        source: 'openclaw-canvas',
        type,
        ...data
      };
      window.parent.postMessage(JSON.stringify(message), '*');
    },

    /**
     * Notify app that canvas is ready
     */
    ready() {
      this.sendMessage('ready');
      console.log('📤 Canvas ready');
    },

    /**
     * Send user action to the app (e.g., button click, form submit)
     */
    sendAction(action, data = {}) {
      this.sendMessage('action', { data: { action, ...data } });
      console.log('📤 Canvas action:', action);
    },

    /**
     * Send an event to the app (e.g., completion, error)
     */
    sendEvent(event, data = {}) {
      this.sendMessage('event', { event, data });
      console.log('📤 Canvas event:', event);
    },

    /**
     * Request navigation to a new URL
     */
    navigate(url) {
      this.sendMessage('navigation', { url });
      console.log('📤 Canvas navigate:', url);
    },

    /**
     * Respond to a command from the app (eval/snapshot)
     */
    sendResponse(requestId, result, error = null) {
      this.sendMessage('response', {
        requestId,
        result,
        error
      });
    },

    /**
     * Register command handlers
     */
    _handlers: {},

    onCommand(command, handler) {
      this._handlers[command] = handler;
    },

    /**
     * Handle incoming message from app
     */
    _handleMessage(event) {
      try {
        const message = JSON.parse(event.data);
        
        // Only handle messages from OpenClaw app
        if (message.source !== 'openclaw-app') return;

        console.log('📨 App → Canvas:', message.type);

        switch (message.type) {
          case 'eval':
            this._handleEval(message);
            break;

          case 'snapshot':
            this._handleSnapshot(message);
            break;

          case 'data':
            this._handleData(message);
            break;

          case 'control':
            this._handleControl(message);
            break;

          default:
            // Check custom handlers
            const handler = this._handlers[message.type];
            if (handler) {
              handler(message.params || {}, message.requestId);
            } else {
              console.warn('Unknown command:', message.type);
            }
        }
      } catch (e) {
        console.error('Canvas message error:', e);
      }
    },

    _handleEval(message) {
      const { requestId, params } = message;
      const js = params?.js;

      if (!js) {
        this.sendResponse(requestId, null, 'No JavaScript provided');
        return;
      }

      try {
        // Execute JavaScript and send result
        const result = eval(js);
        this.sendResponse(requestId, String(result));
      } catch (e) {
        this.sendResponse(requestId, null, String(e.message || e));
      }
    },

    _handleSnapshot(message) {
      const { requestId, params } = message;
      const format = params?.format || 'png';
      const quality = params?.quality || 0.9;

      try {
        // Look for canvas element
        const canvas = document.getElementById('openclaw-canvas') ||
                      document.querySelector('canvas');

        if (!canvas || !canvas.toDataURL) {
          this.sendResponse(requestId, null, 'No canvas element found');
          return;
        }

        const mimeType = format === 'jpeg' || format === 'jpg' ? 'image/jpeg' : 'image/png';
        const dataUrl = canvas.toDataURL(mimeType, quality);
        const base64 = dataUrl.split(',')[1];

        this.sendResponse(requestId, {
          format: format === 'jpg' ? 'jpeg' : format,
          base64
        });
      } catch (e) {
        this.sendResponse(requestId, null, String(e.message || e));
      }
    },

    _handleData(message) {
      const { key, value } = message;
      
      // Dispatch custom event
      const event = new CustomEvent('openclaw-data', {
        detail: { key, value }
      });
      document.dispatchEvent(event);

      // Call handler if registered
      if (this._handlers.data) {
        this._handlers.data({ key, value });
      }
    },

    _handleControl(message) {
      const { action, params } = message;
      
      // Dispatch custom event
      const event = new CustomEvent('openclaw-control', {
        detail: { action, params }
      });
      document.dispatchEvent(event);

      // Call handler if registered
      if (this._handlers.control) {
        this._handlers.control({ action, params });
      }
    }
  };

  // Install message listener
  window.addEventListener('message', openclawCanvas._handleMessage.bind(openclawCanvas));

  // Expose globally
  window.openclawCanvas = openclawCanvas;

  // Auto-ready on load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      openclawCanvas.ready();
    });
  } else {
    openclawCanvas.ready();
  }

  console.log('✅ OpenClaw Canvas Bridge loaded');
})();
