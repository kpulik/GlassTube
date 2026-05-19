//
//  SidebarView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var selectedDestination: NavigationDestination
    @Binding var selectedLibrary: LibraryDestination?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Primary Navigation
                SidebarSection(title: "Navigation") {
                    ForEach(NavigationDestination.allCases) { destination in
                        SidebarButton(
                            title: destination.rawValue,
                            icon: destination.icon,
                            isSelected: selectedDestination == destination && selectedLibrary == nil
                        ) {
                            selectedDestination = destination
                            selectedLibrary = nil
                        }
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Library Section
                SidebarSection(title: "Library") {
                    ForEach(LibraryDestination.allCases) { destination in
                        SidebarButton(
                            title: destination.rawValue,
                            icon: destination.icon,
                            isSelected: selectedLibrary == destination
                        ) {
                            selectedLibrary = destination
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar Components

struct SidebarSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            
            content()
        }
    }
}

struct SidebarButton: View {
    let title: String?
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                
                if let title {
                    Text(title)
                        .font(.body)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isSelected || isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                        .padding(.horizontal, 8)
                        .overlay {
                            if isSelected || isHovered {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.clear)
                                    .glassEffect(.regular.interactive(isHovered), in: .rect(cornerRadius: 8))
                                    .padding(.horizontal, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    SidebarView(
        selectedDestination: .constant(.home),
        selectedLibrary: .constant(nil)
    )
    .frame(width: 240)
}
