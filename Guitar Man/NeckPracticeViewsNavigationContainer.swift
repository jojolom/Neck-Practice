//
//  NavigationContainer.swift
//  Guitar Man
//
//  The trainers are shown two ways: pushed onto Home's navigation stack, and full-screen inside
//  a Daily Practice session. They need a stack for their title and toolbar, but one stack inside
//  another fights over navigation (the first trainer opened after launch popped straight back to
//  Home). So a trainer wraps itself in a NavigationContainer, which only adds a stack when it
//  isn't already in one that says so with `providesNavigationStack`.
//

import SwiftUI

extension EnvironmentValues {
    /// True inside a NavigationStack whose pushed screens should use it rather than start their own.
    @Entry var providesNavigationStack = false
}

/// `content` in a NavigationStack of its own, unless one is already provided.
struct NavigationContainer<Content: View>: View {

    @Environment(\.providesNavigationStack) private var providesNavigationStack
    @ViewBuilder var content: Content

    var body: some View {
        if providesNavigationStack {
            content
        } else {
            NavigationStack { content }
        }
    }
}
