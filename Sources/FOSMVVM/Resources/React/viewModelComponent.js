// viewModelComponent.js
//
// Copyright (c) 2026 FOS Computer Services. All rights reserved.
// Licensed under the Apache License, Version 2.0

/**
 * ViewModelComponent wrapper for FOSMVVM React Applications
 *
 * Wraps React components to add .bind() method that mirrors SwiftUI's ViewModelView.bind() pattern.
 *
 * Usage:
 *   import { viewModelComponent } from '/fosmvvm/react/viewModelComponent.js';
 *
 *   const TaskList = viewModelComponent(({ viewModel }) => {
 *     return <div>{viewModel.title}</div>;
 *   });
 *
 *   export default TaskList;
 *
 *   // Parent usage (mirrors SwiftUI):
 *   <TaskList.bind requestType="GetTasksRequest" params={{ status: 'active' }} />
 */

import React, { useState, useEffect } from 'react';
import {
    BridgeConnectionError,
    BridgeError,
    NetworkError
} from '/fosmvvm/react/wasmBridge.js';

// ============================================================================
// Default Loading Component
// ============================================================================

/**
 * Default loading view shown while fetching ViewModel
 *
 * Can be overridden by passing LoadingView prop to .bind()
 */
const DefaultLoadingView = () => (
    <div className="fosmvvm-loading">
        <div className="fosmvvm-spinner"></div>
        <p>Loading...</p>
    </div>
);

// ============================================================================
// Default Error Component
// ============================================================================

/**
 * Default error view for infrastructure errors
 *
 * Domain errors (NotFoundViewModel, ValidationErrorViewModel, etc.)
 * are passed to the component as ViewModels, not shown here.
 */
const DefaultErrorView = ({ error, retry }) => (
    <div className="fosmvvm-error">
        <h3>Error</h3>
        <p>{error.message}</p>
        {retry && (
            <button onClick={retry}>Retry</button>
        )}
    </div>
);

// ============================================================================
// ViewModelComponent Wrapper
// ============================================================================

/**
 * Wraps a React component to add .bind() method for FOSMVVM pattern
 *
 * @param {React.Component} Component - Component that receives { viewModel } prop
 * @param {Object} options - Configuration options
 * @param {React.Component} options.LoadingView - Custom loading component
 * @param {React.Component} options.ErrorView - Custom error component for infrastructure errors
 * @returns {React.Component} Wrapped component with .bind() method
 */
export function viewModelComponent(Component, options = {}) {
    const {
        LoadingView = DefaultLoadingView,
        ErrorView = DefaultErrorView
    } = options;

    // Create wrapper component that handles .bind() pattern
    const WrappedComponent = (props) => {
        // If viewModel is passed directly, just render the component
        if (props.viewModel) {
            return <Component {...props} />;
        }

        // If using .bind() pattern, viewModel will be in props.bindConfig
        // This shouldn't happen - .bind() creates a different component
        console.error('ViewModelComponent must receive viewModel prop or use .bind()');
        return null;
    };

    // Add .bind() method to wrapped component
    WrappedComponent.bind = function({ requestType, params = {}, ...otherProps }) {
        // Return a component that fetches ViewModel and renders with it
        return function BoundComponent(props) {
            const [state, setState] = useState({
                viewModel: null,
                loading: true,
                error: null
            });

            const fetchViewModel = async () => {
                setState({ viewModel: null, loading: true, error: null });

                try {
                    // Check if WASM bridge is initialized
                    if (!window.wasm || !window.wasm.isInitialized()) {
                        throw new BridgeConnectionError(
                            'WASM bridge not initialized. Ensure wasmBridge.js is loaded and initializeWasmBridge() has been called.'
                        );
                    }

                    // Call WASM bridge to get ViewModel
                    const viewModel = await window.wasm.processRequest(requestType, params);

                    // ViewModel received (could be success or domain error like NotFoundViewModel)
                    // Pass it to the component - it decides how to render
                    setState({ viewModel, loading: false, error: null });

                } catch (error) {
                    // Infrastructure errors (BridgeConnectionError, BridgeError, NetworkError)
                    // are caught here and shown with ErrorView
                    console.error('ViewModelComponent error:', error);
                    setState({ viewModel: null, loading: false, error });
                }
            };

            useEffect(() => {
                fetchViewModel();
            }, [requestType, JSON.stringify(params)]);

            // Show loading state
            if (state.loading) {
                return <LoadingView {...otherProps} {...props} />;
            }

            // Show infrastructure error
            if (state.error) {
                return (
                    <ErrorView
                        error={state.error}
                        retry={fetchViewModel}
                        {...otherProps}
                        {...props}
                    />
                );
            }

            // Render component with ViewModel
            // (ViewModel might be success or domain error - component handles it)
            return <Component viewModel={state.viewModel} {...otherProps} {...props} />;
        };
    };

    return WrappedComponent;
}

// ============================================================================
// Utility: Custom Loading/Error Views
// ============================================================================

/**
 * Configure custom loading and error views globally
 *
 * @param {Object} config
 * @param {React.Component} config.LoadingView - Custom loading component
 * @param {React.Component} config.ErrorView - Custom error component
 */
let globalConfig = {
    LoadingView: DefaultLoadingView,
    ErrorView: DefaultErrorView
};

export function configureViewModelComponent(config) {
    if (config.LoadingView) {
        globalConfig.LoadingView = config.LoadingView;
    }
    if (config.ErrorView) {
        globalConfig.ErrorView = config.ErrorView;
    }
}

/**
 * Get current global configuration
 */
export function getViewModelComponentConfig() {
    return { ...globalConfig };
}

// ============================================================================
// Utility: Preload ViewModel
// ============================================================================

/**
 * Preload a ViewModel without rendering
 *
 * Useful for preloading data before navigation or caching
 *
 * @param {string} requestType - ServerRequest type name
 * @param {Object} params - Request parameters
 * @returns {Promise<Object>} Resolves with ViewModel
 */
export async function preloadViewModel(requestType, params = {}) {
    if (!window.wasm || !window.wasm.isInitialized()) {
        throw new BridgeConnectionError(
            'WASM bridge not initialized'
        );
    }

    return await window.wasm.processRequest(requestType, params);
}

// ============================================================================
// Utility: Invalidate Cache (Future)
// ============================================================================

/**
 * Invalidate cached ViewModels (future enhancement)
 *
 * Currently a no-op. Future versions may implement caching.
 *
 * @param {string} requestType - ServerRequest type to invalidate
 */
export function invalidateViewModel(requestType) {
    // Future: implement cache invalidation
    console.log(`Cache invalidation requested for ${requestType} (not yet implemented)`);
}
