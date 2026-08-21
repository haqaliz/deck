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
}
