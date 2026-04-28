import SwiftUI

struct PersistentTopNavView: View {
    var title: String
    var isTransparent: Bool = false
    var weekLabel: String? = nil
    var onWeekSelector: (() -> Void)? = nil
    var onProfile: () -> Void
    var onChat: () -> Void
    var onCalendar: () -> Void
    var onAddWorkout: (() -> Void)? = nil

    private var iconColor: Color { isTransparent ? .white : .primary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Left zone: profile + chat
                HStack(spacing: 4) {
                    Button(action: onProfile) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 22))
                            .foregroundColor(iconColor)
                            .frame(width: 40, height: 40)
                    }
                    Button(action: onChat) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 20))
                            .foregroundColor(iconColor)
                            .frame(width: 40, height: 40)
                    }
                }

                Spacer()

                // Center zone: week dropdown or static title
                if let label = weekLabel {
                    Button(action: { onWeekSelector?() }) {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(iconColor)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(iconColor)
                        }
                    }
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                Spacer()

                // Right zone: + (manual log) and calendar
                HStack(spacing: 0) {
                    if let onAddWorkout {
                        Button(action: onAddWorkout) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(iconColor)
                                .frame(width: 40, height: 40)
                        }
                    }
                    Button(action: onCalendar) {
                        Image(systemName: "calendar")
                            .font(.system(size: 21))
                            .foregroundColor(iconColor)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            if !isTransparent {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 0.5)
            }
        }
        .background(isTransparent ? Color.clear : Color(.systemBackground))
    }
}
