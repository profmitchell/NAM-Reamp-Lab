//
//  ChainRowView.swift
//  NAM Reamp Lab
//

import SwiftUI

struct ChainRowView: View {
    let chain: ProcessingChain
    
    var body: some View {
        HStack {
            Image(systemName: chain.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(chain.isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.name)
                    .fontWeight(.medium)
                
                Text("\(chain.plugins.count) plugin\(chain.plugins.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .opacity(chain.isEnabled ? 1.0 : 0.6)
    }
}
