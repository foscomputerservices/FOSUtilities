// fosmvvmWasmRuntime.js
//
// Copyright (c) 2026 FOS Computer Services. All rights reserved.
// Licensed under the Apache License, Version 2.0

/**
 * FOSMVVM WASM Runtime for React Applications
 *
 * Provides JavaScript → Swift WASM communication for ServerRequest processing.
 *
 * Usage:
 *   // After WASM module is loaded:
 *   window.FOSMVVM.initializeWasmRuntime(wasmInstance);
 *
 *   // Then use window.wasm.processRequest():
 *   const viewModel = await window.wasm.processRequest('GetTasksRequest', { status: 'active' });
 */

// Establish FOSMVVM namespace
window.FOSMVVM = window.FOSMVVM || {};

// ============================================================================
// Error Types
// ============================================================================

/**
 * Thrown when WASM Runtime is not initialized or connection failed
 */
window.FOSMVVM.WasmRuntimeConnectionError = class WasmRuntimeConnectionError extends Error {
    constructor(message) {
        super(message);
        this.name = 'WasmRuntimeConnectionError';
    }
};

/**
 * Thrown when WASM Runtime function execution fails
 */
window.FOSMVVM.WasmRuntimeError = class WasmRuntimeError extends Error {
    constructor(message, originalError) {
        super(message);
        this.name = 'WasmRuntimeError';
        this.originalError = originalError;
    }
};

/**
 * Thrown when network request fails (if using HTTP runtime instead of WASM)
 */
window.FOSMVVM.NetworkError = class NetworkError extends Error {
    constructor(message, status) {
        super(message);
        this.name = 'NetworkError';
        this.status = status;
    }
};

// ============================================================================
// FOSMVVM WASM Runtime Implementation
// ============================================================================

let wasmInstance = null;
let isInitialized = false;

/**
 * Initialize the FOSMVVM WASM Runtime with a loaded WASM module instance
 *
 * @param {Object} wasm - The loaded WASM module instance
 * @throws {Error} If wasm instance doesn't have required processRequest function
 */
window.FOSMVVM.initializeWasmRuntime = function(wasm) {
    if (!wasm) {
        throw new Error('WASM instance is required');
    }

    if (typeof wasm.processRequest !== 'function') {
        throw new Error('WASM instance must export a processRequest function');
    }

    wasmInstance = wasm;
    isInitialized = true;

    // Initialize global API
    if (!window.wasm) {
        window.wasm = {};
    }

    window.wasm.processRequest = processRequest;
    window.wasm.isInitialized = () => isInitialized;
};

/**
 * Process a ServerRequest via FOSMVVM WASM Runtime
 *
 * @param {string} requestType - The ServerRequest type name (e.g., "GetTasksRequest")
 * @param {Object} params - Request parameters (query, fragment, or body)
 * @returns {Promise<Object>} Resolves with ViewModel (success or domain error)
 * @throws {WasmRuntimeConnectionError} If WASM Runtime not initialized
 * @throws {WasmRuntimeError} If WASM Runtime function execution fails
 */
async function processRequest(requestType, params = {}) {
    const WasmRuntimeConnectionError = window.FOSMVVM.WasmRuntimeConnectionError;
    const WasmRuntimeError = window.FOSMVVM.WasmRuntimeError;

    if (!isInitialized || !wasmInstance) {
        throw new WasmRuntimeConnectionError(
            'FOSMVVM WASM Runtime not initialized. Call initializeWasmRuntime(wasm) first.'
        );
    }

    try {
        // Convert params object to JSON string
        const paramsJSON = JSON.stringify(params);

        // Call Swift WASM function
        // Expected signature: processRequest(typeName: String, paramsJSON: String) -> String
        const responseJSON = await wasmInstance.processRequest(requestType, paramsJSON);

        // Parse response JSON string → JavaScript object
        const response = JSON.parse(responseJSON);

        // Response should be a ViewModel (success or domain error)
        // Domain errors flow through as ViewModels, not thrown exceptions
        return response;

    } catch (error) {
        // Infrastructure errors are thrown
        if (error instanceof WasmRuntimeConnectionError) {
            throw error;
        }

        throw new WasmRuntimeError(
            `FOSMVVM WASM Runtime error processing ${requestType}: ${error.message}`,
            error
        );
    }
}

/**
 * Check if FOSMVVM WASM Runtime is initialized
 *
 * @returns {boolean} True if runtime is ready to use
 */
window.FOSMVVM.isWasmRuntimeInitialized = function() {
    return isInitialized;
};

/**
 * Reset the FOSMVVM WASM Runtime (useful for testing)
 */
window.FOSMVVM.resetWasmRuntime = function() {
    wasmInstance = null;
    isInitialized = false;

    if (window.wasm) {
        delete window.wasm.processRequest;
        delete window.wasm.isInitialized;
    }
};

// ============================================================================
// HTTP Fallback Runtime (Optional)
// ============================================================================

/**
 * Initialize HTTP fallback runtime for environments without WASM support
 *
 * This provides the same window.wasm.processRequest() API but uses HTTP
 * requests to a Vapor server instead of WASM.
 *
 * @param {string} baseURL - Base URL for ServerRequest endpoints (e.g., "https://api.example.com")
 */
window.FOSMVVM.initializeHttpRuntime = function(baseURL) {
    if (!baseURL) {
        throw new Error('Base URL is required for HTTP runtime');
    }

    isInitialized = true;

    if (!window.wasm) {
        window.wasm = {};
    }

    window.wasm.processRequest = async (requestType, params = {}) => {
        const NetworkError = window.FOSMVVM.NetworkError;

        try {
            // POST to /api/{requestType}
            const url = `${baseURL}/api/${requestType}`;

            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(params)
            });

            if (!response.ok) {
                throw new NetworkError(
                    `HTTP ${response.status}: ${response.statusText}`,
                    response.status
                );
            }

            // Parse response ViewModel
            const viewModel = await response.json();
            return viewModel;

        } catch (error) {
            if (error instanceof NetworkError) {
                throw error;
            }

            throw new NetworkError(
                `Network error processing ${requestType}: ${error.message}`,
                0
            );
        }
    };

    window.wasm.isInitialized = () => isInitialized;
};
