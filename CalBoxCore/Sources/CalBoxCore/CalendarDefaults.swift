import Foundation

// MARK: - Which calendars start ticked

public enum CalendarDefaults {
    /// A calendar starts enabled when the user can write to it.
    ///
    /// Read-only calendars are the feeds — holidays, birthdays, subscriptions —
    /// whose all-day entries would otherwise swamp the agenda. Writability is
    /// the signal because it is locale-independent: matching a `"Holidays"`
    /// title prefix misses `Feiertage in Deutschland`, and `sourceType` /
    /// `isSubscribed` miss holiday calendars delivered as plain CalDAV.
    /// Verified against this machine's 11 calendars: false for exactly
    /// `US Holidays`, `Holidays in Canada`, `Holidays in Iran` and `Birthdays`.
    public static func shouldEnableByDefault(allowsContentModifications: Bool) -> Bool {
        allowsContentModifications
    }

    /// The calendars to actually read.
    ///
    /// Until the user has been through the picker there is no stored choice,
    /// so the default rule is applied live — otherwise a freshly added widget
    /// would sit empty until someone happened to open settings, which is the
    /// worst first run of any Deck widget. Once they have chosen, their list
    /// is authoritative: unticking everything means everything, not "fall back
    /// to the defaults".
    public static func resolve(
        selected: [String],
        hasChosen: Bool,
        available: [(id: String, allowsContentModifications: Bool)]
    ) -> [String] {
        if hasChosen { return selected }
        return available
            .filter { shouldEnableByDefault(allowsContentModifications: $0.allowsContentModifications) }
            .map(\.id)
    }
}
