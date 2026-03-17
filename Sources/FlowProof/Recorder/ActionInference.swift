import Foundation

/// Converts raw captured events into high-level workflow actions
class ActionInference {
    private let keystrokeTimeout: TimeInterval = 0.5
    private let pauseThreshold: TimeInterval = 3.0
    private let clickRepeatWindow: TimeInterval = 5.0
    private let repeatThreshold = 3

    /// Process a list of captured events and infer workflow steps
    func inferActions(from events: [CapturedEvent]) -> [InferredAction] {
        guard !events.isEmpty else { return [] }

        // Step 1: Group related events
        var eventGroups = mergeKeystrokes(events)
        eventGroups = detectDrags(eventGroups)
        eventGroups = detectShortcuts(eventGroups)

        // Step 2: Convert groups to actions
        var actions = eventGroups.compactMap { group -> InferredAction? in
            actionFromGroup(group)
        }

        // Step 3: Insert wait steps for pauses
        actions = insertWaits(actions)

        // Step 4: Clean up
        actions = filterAccidentalClicks(actions)
        actions = collapseRepeats(actions)

        return actions
    }

    /// Merge sequential keystrokes into type actions
    private func mergeKeystrokes(_ events: [CapturedEvent]) -> [EventGroup] {
        var groups: [EventGroup] = []
        var currentKeystrokes: [CapturedEvent] = []
        var lastKeystrokeTime: Date?

        for event in events {
            switch event.eventType {
            case .keyDown:
                if let lastTime = lastKeystrokeTime,
                   event.timestamp.timeIntervalSince(lastTime) > keystrokeTimeout {
                    if !currentKeystrokes.isEmpty {
                        let characters = currentKeystrokes.compactMap { e -> String? in
                            if case .keyDown = e.eventType {
                                return e.characters
                            }
                            return nil
                        }.joined()
                        groups.append(EventGroup(events: currentKeystrokes, groupType: .typing(text: characters)))
                        currentKeystrokes.removeAll()
                    }
                }
                currentKeystrokes.append(event)
                lastKeystrokeTime = event.timestamp

            case .keyUp:
                currentKeystrokes.append(event)
                lastKeystrokeTime = event.timestamp

            default:
                if !currentKeystrokes.isEmpty {
                    let characters = currentKeystrokes.compactMap { e -> String? in
                        if case .keyDown = e.eventType {
                            return e.characters
                        }
                        return nil
                    }.joined()
                    groups.append(EventGroup(events: currentKeystrokes, groupType: .typing(text: characters)))
                    currentKeystrokes.removeAll()
                    lastKeystrokeTime = nil
                }

                switch event.eventType {
                case .mouseMoved:
                    if groups.last?.groupType != .mouseMoved {
                        groups.append(EventGroup(events: [event], groupType: .mouseMoved))
                    }

                case .scrollWheel(let deltaX, let deltaY):
                    let direction: InferredScrollDirection = deltaY > 0 ? .down : .up
                    let amount = Int(abs(deltaY).rounded())
                    groups.append(EventGroup(events: [event], groupType: .scroll(direction: direction, amount: max(1, amount))))

                default:
                    groups.append(EventGroup(events: [event], groupType: .single(event.eventType)))
                }
            }
        }

        if !currentKeystrokes.isEmpty {
            let characters = currentKeystrokes.compactMap { e -> String? in
                if case .keyDown = e.eventType {
                    return e.characters
                }
                return nil
            }.joined()
            groups.append(EventGroup(events: currentKeystrokes, groupType: .typing(text: characters)))
        }

        return groups
    }

    /// Detect drag operations (mouseDown + mouseMoved + mouseUp)
    private func detectDrags(_ groups: [EventGroup]) -> [EventGroup] {
        var result: [EventGroup] = []
        var i = 0

        while i < groups.count {
            let group = groups[i]

            if case .single(let eventType) = group.groupType,
               case .mouseDown = eventType {
                var dragEvents = group.events
                var moveCount = 0

                // Collect subsequent mouseMoved events
                var j = i + 1
                while j < groups.count {
                    if case .single(.mouseMoved) = groups[j].groupType {
                        dragEvents.append(contentsOf: groups[j].events)
                        moveCount += 1
                        j += 1
                    } else {
                        break
                    }
                }

                // Look for mouseUp
                if j < groups.count,
                   case .single(let nextEventType) = groups[j].groupType,
                   case .mouseUp = nextEventType,
                   moveCount > 0 {
                    dragEvents.append(contentsOf: groups[j].events)

                    let startPos = group.events[0].position ?? .zero
                    let endPos = dragEvents.last?.position ?? startPos

                    result.append(EventGroup(events: dragEvents, groupType: .drag(from: startPos, to: endPos)))
                    i = j + 1
                    continue
                }
            }

            result.append(group)
            i += 1
        }

        return result
    }

    /// Detect keyboard shortcuts (modifier + key combos)
    private func detectShortcuts(_ groups: [EventGroup]) -> [EventGroup] {
        var result: [EventGroup] = []
        var i = 0

        while i < groups.count {
            let group = groups[i]

            if case .single(.keyDown) = group.groupType,
               !group.events.isEmpty {
                let event = group.events[0]
                let hasModifier = !event.modifiers.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty

                if hasModifier {
                    var comboName = ""

                    if event.modifiers.contains(.maskCommand) {
                        comboName += "cmd+"
                    }
                    if event.modifiers.contains(.maskControl) {
                        comboName += "ctrl+"
                    }
                    if event.modifiers.contains(.maskAlternate) {
                        comboName += "opt+"
                    }
                    if event.modifiers.contains(.maskShift) {
                        comboName += "shift+"
                    }

                    if let chars = event.characters {
                        comboName += chars
                    }

                    result.append(EventGroup(events: group.events, groupType: .shortcut(combo: comboName)))
                    i += 1
                    continue
                }
            }

            result.append(group)
            i += 1
        }

        return result
    }

    /// Collapse repeated identical actions into loops
    private func collapseRepeats(_ actions: [InferredAction]) -> [InferredAction] {
        guard actions.count >= repeatThreshold else { return actions }

        var result: [InferredAction] = []
        var i = 0

        while i < actions.count {
            let currentAction = actions[i]
            var repeatCount = 1
            var j = i + 1

            while j < actions.count {
                let nextAction = actions[j]
                let timeDiff = nextAction.timestamp.timeIntervalSince(currentAction.timestamp)

                if actionsAreIdentical(currentAction, nextAction) &&
                   timeDiff < clickRepeatWindow {
                    repeatCount += 1
                    j += 1
                } else {
                    break
                }
            }

            if repeatCount >= repeatThreshold {
                var loopAction = currentAction
                loopAction.amount = repeatCount
                result.append(loopAction)
                i = j
            } else {
                result.append(currentAction)
                i += 1
            }
        }

        return result
    }

    /// Filter out accidental clicks (click + immediate undo)
    private func filterAccidentalClicks(_ actions: [InferredAction]) -> [InferredAction] {
        var result: [InferredAction] = []
        var i = 0

        while i < actions.count {
            let action = actions[i]

            if i + 1 < actions.count {
                let nextAction = actions[i + 1]

                // Check for command+z (undo) within 1 second of a click
                if case .click = action.action {
                    if let nextCombo = nextAction.combo, nextCombo.contains("cmd+z"),
                       nextAction.timestamp.timeIntervalSince(action.timestamp) < 1.0 {
                        i += 2
                        continue
                    }
                }
            }

            result.append(action)
            i += 1
        }

        return result
    }

    /// Insert wait steps for pauses > 3 seconds
    private func insertWaits(_ actions: [InferredAction]) -> [InferredAction] {
        guard actions.count > 1 else { return actions }

        var result: [InferredAction] = []

        for i in 0..<actions.count {
            result.append(actions[i])

            if i + 1 < actions.count {
                let currentAction = actions[i]
                let nextAction = actions[i + 1]
                let timeDiff = nextAction.timestamp.timeIntervalSince(currentAction.timestamp)

                if timeDiff > pauseThreshold {
                    let waitAction = InferredAction(
                        timestamp: currentAction.timestamp.addingTimeInterval(pauseThreshold),
                        action: .wait(seconds: Int(timeDiff)),
                        target: nil,
                        text: nil,
                        combo: nil,
                        from: nil,
                        to: nil,
                        duration: timeDiff,
                        direction: nil,
                        amount: nil,
                        suggestedName: "Wait \(Int(timeDiff))s"
                    )
                    result.append(waitAction)
                }
            }
        }

        return result
    }

    /// Choose the best targeting strategy for each action
    private func selectTargetingStrategy(for element: ElementInfo?) -> InferredElementTarget? {
        guard let element = element else { return nil }

        if let identifier = element.identifier {
            return InferredElementTarget(strategy: .identifier, value: identifier)
        }

        if let label = element.label {
            return InferredElementTarget(strategy: .label, value: label)
        }

        if let frame = element.frame {
            return InferredElementTarget(strategy: .coordinates, value: "\(Int(frame.midX)),\(Int(frame.midY))")
        }

        return nil
    }

    // MARK: - Helper Methods

    private func actionsAreIdentical(_ a1: InferredAction, _ a2: InferredAction) -> Bool {
        switch (a1.action, a2.action) {
        case (.click, .click):
            return true
        case (.type(let t1), .type(let t2)):
            return t1 == t2
        case (.scroll(let d1, let a1), .scroll(let d2, let a2)):
            return d1 == d2 && a1 == a2
        default:
            return false
        }
    }

    private func actionFromGroup(_ group: EventGroup) -> InferredAction? {
        let timestamp = group.events.first?.timestamp ?? Date()
        let element = group.events.first?.elementInfo

        switch group.groupType {
        case .single(let eventType):
            switch eventType {
            case .mouseDown(let button, _):
                let target = selectTargetingStrategy(for: element)
                return InferredAction(
                    timestamp: timestamp,
                    action: .click(button: button),
                    target: target,
                    text: nil,
                    combo: nil,
                    from: nil,
                    to: nil,
                    duration: nil,
                    direction: nil,
                    amount: nil,
                    suggestedName: "Click \(button == 0 ? "Left" : "Right")"
                )

            default:
                return nil
            }

        case .drag(let from, let to):
            let fromTarget = InferredElementTarget(strategy: .coordinates, value: "\(Int(from.x)),\(Int(from.y))")
            let toTarget = InferredElementTarget(strategy: .coordinates, value: "\(Int(to.x)),\(Int(to.y))")
            let distance = Int(hypot(to.x - from.x, to.y - from.y))
            return InferredAction(
                timestamp: timestamp,
                action: .drag,
                target: fromTarget,
                text: nil,
                combo: nil,
                from: fromTarget,
                to: toTarget,
                duration: nil,
                direction: nil,
                amount: distance,
                suggestedName: "Drag \(distance)px"
            )

        case .typing(let text):
            return InferredAction(
                timestamp: timestamp,
                action: .type(text: text),
                target: element != nil ? selectTargetingStrategy(for: element) : nil,
                text: text,
                combo: nil,
                from: nil,
                to: nil,
                duration: nil,
                direction: nil,
                amount: nil,
                suggestedName: "Type '\(text)'"
            )

        case .shortcut(let combo):
            return InferredAction(
                timestamp: timestamp,
                action: .shortcut(combo: combo),
                target: nil,
                text: nil,
                combo: combo,
                from: nil,
                to: nil,
                duration: nil,
                direction: nil,
                amount: nil,
                suggestedName: "Press \(combo)"
            )

        case .scroll(let direction, let amount):
            return InferredAction(
                timestamp: timestamp,
                action: .scroll(direction: direction, amount: amount),
                target: nil,
                text: nil,
                combo: nil,
                from: nil,
                to: nil,
                duration: nil,
                direction: direction,
                amount: amount,
                suggestedName: "Scroll \(direction) \(amount)"
            )

        case .pause(let duration):
            return InferredAction(
                timestamp: timestamp,
                action: .wait(seconds: Int(duration)),
                target: nil,
                text: nil,
                combo: nil,
                from: nil,
                to: nil,
                duration: duration,
                direction: nil,
                amount: nil,
                suggestedName: "Wait \(Int(duration))s"
            )

        case .mouseMoved:
            return nil
        }
    }
}

// MARK: - Recorder-specific types (separate from WorkflowModels canonical types)

struct InferredAction {
    let timestamp: Date
    let action: InferredActionType
    var target: InferredElementTarget?
    let text: String?
    let combo: String?
    let from: InferredElementTarget?
    let to: InferredElementTarget?
    let duration: TimeInterval?
    let direction: InferredScrollDirection?
    var amount: Int?
    let suggestedName: String
}

enum InferredActionType: Equatable {
    case click(button: Int)
    case type(text: String)
    case shortcut(combo: String)
    case drag
    case scroll(direction: InferredScrollDirection, amount: Int)
    case wait(seconds: Int)
}

struct InferredElementTarget: Hashable {
    let strategy: TargetingStrategy
    let value: String
}

enum TargetingStrategy: String {
    case identifier
    case label
    case role
    case coordinates
    case xpath
}

enum InferredScrollDirection: String {
    case up
    case down
    case left
    case right
}

/// Group of related events (e.g., a drag = mouseDown + moves + mouseUp)
struct EventGroup {
    let events: [CapturedEvent]
    let groupType: EventGroupType
}

enum EventGroupType: Equatable {
    case single(CapturedEventType)
    case drag(from: CGPoint, to: CGPoint)
    case shortcut(combo: String)
    case scroll(direction: InferredScrollDirection, amount: Int)
    case typing(text: String)
    case pause(duration: TimeInterval)
    case mouseMoved

    static func == (lhs: EventGroupType, rhs: EventGroupType) -> Bool {
        switch (lhs, rhs) {
        case (.mouseMoved, .mouseMoved):
            return true
        case (.drag(let f1, let t1), .drag(let f2, let t2)):
            return f1 == f2 && t1 == t2
        case (.shortcut(let c1), .shortcut(let c2)):
            return c1 == c2
        case (.scroll(let d1, let a1), .scroll(let d2, let a2)):
            return d1 == d2 && a1 == a2
        case (.typing(let t1), .typing(let t2)):
            return t1 == t2
        case (.pause(let d1), .pause(let d2)):
            return abs(d1 - d2) < 0.1
        case (.single(let e1), .single(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}
