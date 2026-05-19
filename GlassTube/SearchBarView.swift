//
//  SearchBarView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    var onSearch: () -> Void = {}
    @State private var isHovered = false
    @State private var isFocused = false
    @FocusState private var focusState: Bool

    private let collapsedWidth: CGFloat = 430
    private let focusedWidth: CGFloat = 600
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14, weight: .medium))

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .focused($focusState)
                .onSubmit {
                    performSearch()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 18)

            Button(action: performSearch) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: isFocused ? focusedWidth : collapsedWidth)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? Color.accentColor.opacity(0.45)
                        : Color.primary.opacity(isHovered ? 0.22 : 0.12),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onTapGesture {
            focusState = true
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onChange(of: focusState) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isFocused = newValue
            }
        }
    }
    
    private func performSearch() {
        guard !text.isEmpty else { return }
        onSearch()
    }
}

#Preview {
    SearchBarView(text: .constant(""))
        .frame(width: 600)
        .padding()
}

#Preview("With Text") {
    SearchBarView(text: .constant("Swift programming"))
        .frame(width: 600)
        .padding()
}
