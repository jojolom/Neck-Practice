//
//  ContentView.swift
//  Guitar Man
//
//  Created by Joe Lombardi on 2/16/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Quiz", systemImage: "questionmark.circle.fill") {
                QuizView()
            }
            Tab("Explore", systemImage: "guitars.fill") {
                ExploreView()
            }
        }
    }
}

#Preview {
    ContentView()
}
