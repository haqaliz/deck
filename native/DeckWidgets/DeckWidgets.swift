import WidgetKit
import SwiftUI

@main
struct DeckWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LiveBoxWidget()
        OpenBoxWidget()
        NetBoxWidget()
        BatBoxWidget()
        GitBoxWidget()
        DevBoxWidget()
        ClipBoxWidget()
        WeatherBoxWidget()
        ClockBoxWidget()
        ShipBoxWidget()
        TaskBoxWidget()
        CalBoxWidget()
    }
}
