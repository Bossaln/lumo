import Foundation
import Testing
@testable import NotchaiCore

private let t0 = ContinuousClock.now
private func question(_ id: UUID = UUID()) -> SignalContent {
    SignalContent(id: id, agent: .codex, title: "notchai · Codex", subtitle: "Welche Farbe?", kind: .question(options: ["Rot"]))
}
private func permission(_ id: UUID = UUID()) -> SignalContent {
    SignalContent(id: id, agent: .claude, title: "notchai · Claude", subtitle: "Möchte ausführen:", detail: "ls", kind: .permission)
}
private func done(_ id: UUID = UUID()) -> SignalContent {
    SignalContent(id: id, agent: .claude, title: "notchai · Claude", subtitle: "Fertig", kind: .done)
}

@Test func raiseShowsSignal() {
    var life = SignalLifecycle()
    let q = question()
    #expect(life.raise(q, now: t0) == nil)
    #expect(life.active?.content == q)
    #expect(life.active?.id == q.id)
}
@Test func raiseReplacesAndReturnsTheReplacedSignal() {
    var life = SignalLifecycle()
    let a = permission(), b = question()
    life.raise(a, now: t0)
    #expect(life.raise(b, now: t0)?.content == a)
    #expect(life.active?.content == b)
}
@Test func clearingAReplacedSignalLeavesTheNewOne() {
    // Ein später Klick oder Timer für das alte Signal darf das neue nicht schließen.
    var life = SignalLifecycle()
    let a = permission(), b = permission()
    life.raise(a, now: t0)
    life.raise(b, now: t0)
    #expect(life.clear(a.id) == nil)
    #expect(life.active?.content == b)
    #expect(life.clear(b.id)?.content == b)
    #expect(life.active == nil)
}
@Test func clearActiveClosesWhateverIsShown() {
    var life = SignalLifecycle()
    #expect(life.clearActive() == nil)
    let a = done()
    life.raise(a, now: t0)
    #expect(life.clearActive()?.content == a)
    #expect(life.active == nil)
}
@Test func doneExpiresAfterFourSeconds() {
    var life = SignalLifecycle()
    life.raise(done(), now: t0)
    #expect(life.active?.dismissAt == t0 + .seconds(4))
    #expect(life.expire(now: t0 + .milliseconds(3999)) == nil)
    #expect(life.active != nil)
    #expect(life.expire(now: t0 + .seconds(4)) != nil)
    #expect(life.active == nil)
}
@Test func expiryOfAReplacedDoneKeepsTheSuccessor() {
    var life = SignalLifecycle()
    life.raise(done(), now: t0)
    let p = permission()
    life.raise(p, now: t0 + .seconds(1))
    #expect(life.active?.dismissAt == nil)
    #expect(life.expire(now: t0 + .seconds(10)) == nil)
    #expect(life.active?.content == p)
}
@Test func twoEqualLookingDoneSignalsAreDistinct() {
    // Gleicher Text, aber zwei Signale: Das zweite bekommt seine eigene Frist.
    var life = SignalLifecycle()
    life.raise(done(), now: t0)
    let second = done()
    #expect(life.raise(second, now: t0 + .seconds(3)) != nil)
    #expect(life.expire(now: t0 + .seconds(5)) == nil)
    #expect(life.active?.content == second)
    #expect(life.expire(now: t0 + .seconds(7)) != nil)
}
@Test func reraisingTheSameSignalKeepsDraftAndRestartsTimer() {
    // Dieselbe Anfrage (gleiche ID) kann erneut gemeldet werden.
    var life = SignalLifecycle()
    let id = UUID()
    life.raise(question(id), now: t0)
    life.setDraft("Bl", for: id)
    #expect(life.raise(question(id), now: t0 + .seconds(1)) == nil)
    #expect(life.draft(for: id) == "Bl")
    life.raise(done(id), now: t0 + .seconds(2))
    #expect(life.active?.dismissAt == t0 + .seconds(6))
}
@Test func draftBelongsToItsSignal() {
    var life = SignalLifecycle()
    let a = question(), b = question()
    life.raise(a, now: t0)
    life.setDraft("Blau", for: a.id)
    #expect(life.draft(for: a.id) == "Blau")
    life.raise(b, now: t0)
    // Der Entwurf für A taucht nicht bei B auf, und A kann B nichts mehr unterschieben.
    #expect(life.draft(for: b.id) == "")
    life.setDraft("Rot", for: a.id)
    #expect(life.draft(for: b.id) == "")
    #expect(life.draft(for: a.id) == "")
    life.clear(b.id)
    #expect(life.draft(for: b.id) == "")
}
@Test func actionsOnlyReachTheSignalTheyWereMadeFor() {
    var life = SignalLifecycle()
    let p = permission(), q = question()
    life.raise(p, now: t0)
    #expect(life.accepts(.allow, for: p.id))
    life.raise(q, now: t0)
    // Ein „Erlauben“ für die ersetzte Freigabe trifft die neue Frage nicht.
    #expect(!life.accepts(.allow, for: p.id))
    #expect(!life.accepts(.answer("Rot"), for: p.id))
    #expect(life.accepts(.answer("Rot"), for: q.id))
    life.clear(q.id)
    #expect(!life.accepts(.answer("Rot"), for: q.id))
}
@Test func actionsMustFitTheKind() {
    #expect(SignalKind.permission.permits(.allow))
    #expect(SignalKind.permission.permits(.deny))
    #expect(SignalKind.permission.permits(.dismiss))
    #expect(!SignalKind.permission.permits(.answer("Ja")))
    #expect(SignalKind.question(options: []).permits(.answer("Ja")))
    #expect(SignalKind.question(options: []).permits(.dismiss))
    #expect(!SignalKind.question(options: []).permits(.allow))
    #expect(!SignalKind.question(options: []).permits(.deny))
    #expect(SignalKind.done.permits(.dismiss))
    #expect(!SignalKind.done.permits(.allow))
    #expect(SignalKind.error.permits(.dismiss))
    #expect(!SignalKind.error.permits(.answer("x")))
}
