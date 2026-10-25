import Testing
@testable import LumoCore

@Test func enablingLoginItemRegistersIt() throws {
    var registered = 0
    var unregistered = 0

    LoginItemRegistration.perform(
        enabled: true,
        register: { registered += 1 },
        unregister: { unregistered += 1 }
    )

    #expect(registered == 1)
    #expect(unregistered == 0)
}

@Test func disablingLoginItemUnregistersIt() throws {
    var registered = 0
    var unregistered = 0

    LoginItemRegistration.perform(
        enabled: false,
        register: { registered += 1 },
        unregister: { unregistered += 1 }
    )

    #expect(registered == 0)
    #expect(unregistered == 1)
}

@Test func loginItemErrorsArePropagated() {
    enum Failure: Error { case registration }
    var didThrow = false

    do {
        try LoginItemRegistration.perform(
            enabled: true,
            register: { throw Failure.registration },
            unregister: {}
        )
    } catch Failure.registration {
        didThrow = true
    } catch {}

    #expect(didThrow)
}
