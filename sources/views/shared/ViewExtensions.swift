import SwiftUI

extension View {
    @ViewBuilder
    func errorTint(_ isError: Bool) -> some View {
        if isError {
            self.tint(.red)
        } else {
            self
        }
    }
}
