//
//  MainWindowAccessor.swift
//  ClaudeIsland
//
//  Lightweight NSView bridge used to grab the hosting NSWindow.
//

import AppKit
import SwiftUI

struct MainWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> MainWindowResolverView {
        let view = MainWindowResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: MainWindowResolverView, context: Context) {
        nsView.onResolve = onResolve
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            nsView.onResolve?(window)
        }
    }
}

final class MainWindowResolverView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.onResolve?(window)
        }
    }
}
