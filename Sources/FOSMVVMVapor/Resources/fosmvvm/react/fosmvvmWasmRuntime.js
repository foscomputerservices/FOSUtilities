// fosmvvmWasmRuntime.js
//
// Copyright (c) 2026 FOS Computer Services. All rights reserved.
// Licensed under the Apache License, Version 2.0

/**
 * WASM Bridge for FOSMVVM React Applications
 *
 * Provides JavaScript → Swift WASM communication for ServerRequest processing.
 *
 * Usage:
 *   import { initializeWasmBridge } from '/fosmvvm/react/fosmvvmWasmRuntime.js';
 *
 *   // After WASM module is loaded:
 *   initializeWasmBridge(wasmInstance);
 *
 *   // Then use window.wasm.processRequest():
 *   const viewModel = await window.wasm.processRequest('GetTasksRequest', { status: 'active' });
 */

// ============================================================================
// Error Types
// ============================================================================

/**
 * Thrown when WASM module is not loaded or connection failed
 */
export class BridgeConnectionError extends Error {
    constructor(message) {
        super(message);
        this.name = 'BridgeConnectionError';
    }
}

/**
 * Thrown when WASM function execution fails
 */
export class BridgeError extends Error {
    constructor(message, originalError) {
        super(message);
        this.name = 'BridgeError';
        this.originalError = originalError;
    }
}

/**
 * Thrown when network request fails (if using HTTP bridge instead of WASM)
 */
export class NetworkError extends Error {
    constructor(message, status) {
        super(message);
        this.name = 'NetworkError';
        this.status = status;
    }
}

// ============================================================================
// WASM Bridge Implementation
// ============================================================================

let wasmInstance = null;
let isInitialized = false;

/**
 * Initialize the WASM bridge with a loaded WASM module instance
 *
 * @param {Object} wasm - The loaded WASM module instance
 * @throws {Error} If wasm instance doesn't have required processRequest function
 */
export function initializeWasmBridge(wasm) {
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
}

/**
 * Process a ServerRequest via WASM bridge
 *
 * @param {string} requestType - The ServerRequest type name (e.g., "GetTasksRequest")
 * @param {Object} params - Request parameters (query, fragment, or body)
 * @returns {Promise<Object>} Resolves with ViewModel (success or domain error)
 * @throws {BridgeConnectionError} If WASM bridge not initialized
 * @throws {BridgeError} If WASM function execution fails
 */
async function processRequest(requestType, params = {}) {
    if (!isInitialized || !wasmInstance) {
        throw new BridgeConnectionError(
            'WASM bridge not initialized. Call initializeWasmBridge(wasm) first.'
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
        if (error instanceof BridgeConnectionError) {
            throw error;
        }

        throw new BridgeError(
            `WASM bridge error processing ${requestType}: ${error.message}`,
            error
        );
    }
}

/**
 * Check if WASM bridge is initialized
 *
 * @returns {boolean} True if bridge is ready to use
 */
export function isWasmBridgeInitialized() {
    return isInitialized;
}

/**
 * Reset the WASM bridge (useful for testing)
 */
export function resetWasmBridge() {
    wasmInstance = null;
    isInitialized = false;

    if (window.wasm) {
        delete window.wasm.processRequest;
        delete window.wasm.isInitialized;
    }
}

// ============================================================================
// HTTP Fallback Bridge (Optional)
// ============================================================================

/**
 * Initialize HTTP fallback bridge for environments without WASM support
 *
 * This provides the same window.wasm.processRequest() API but uses HTTP
 * requests to a Vapor server instead of WASM.
 *
 * @param {string} baseURL - Base URL for ServerRequest endpoints (e.g., "https://api.example.com")
 */
export function initializeHttpBridge(baseURL) {
    if (!baseURL) {
        throw new Error('Base URL is required for HTTP bridge');
    }

    isInitialized = true;

    if (!window.wasm) {
        window.wasm = {};
    }

    window.wasm.processRequest = async (requestType, params = {}) => {
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
}
