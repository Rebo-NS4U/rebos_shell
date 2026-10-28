pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

ColumnLayout {
    id: root
    spacing: 10

    readonly property bool fahrenheit: Config.weather.unit === "F"
    readonly property string speedUnit: fahrenheit ? "mph" : "km/h"

    function number(value: real, suffix: string): string {
        return Number.isFinite(value) ? Math.round(value) + suffix : "—";
    }

    function speed(value: real): string {
        return number(fahrenheit ? value / 1.609344 : value, " " + speedUnit);
    }

    function timeLabel(time: string): string {
        if (!time)
            return "—";
        const parts = time.split(":");
        const hour = Number(parts[0]);
        return Config.bar.use12hFormat ? (hour % 12 || 12) + ":" + parts[1] + (hour < 12 ? " am" : " pm") : time;
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: metrics.implicitHeight + 20
        variant: "internalbg"
        radius: Styling.radius(2)

        GridLayout {
            id: metrics
            anchors.fill: parent
            anchors.margins: 10
            columns: 3
            columnSpacing: 8
            rowSpacing: 12

            Repeater {
                model: [
                    {label: "Feels like", value: root.number(WeatherService.feelsLike, "°" + Config.weather.unit)},
                    {label: "Humidity", value: root.number(WeatherService.humidity, "%")},
                    {label: "Rain today", value: root.number(WeatherService.rainChance, "%")},
                    {label: "Wind", value: root.speed(WeatherService.windSpeed)},
                    {label: "Gusts", value: root.speed(WeatherService.windGusts)},
                    {label: "UV peak", value: Number.isFinite(WeatherService.uvIndex) ? WeatherService.uvIndex.toFixed(1) : "—"}
                ]
                ColumnLayout {
                    id: metric
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 3
                    StyledText {
                        text: metric.modelData.label
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }
                    StyledText {
                        text: metric.modelData.value
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.overBackground
                    }
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: hoursColumn.implicitHeight + 20
        visible: WeatherService.hourlyForecast.length > 0
        variant: "internalbg"
        radius: Styling.radius(2)

        ColumnLayout {
            id: hoursColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            StyledText {
                text: "Next hours"
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: WeatherService.hourlyForecast
                    ColumnLayout {
                        id: hour
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: (hoursColumn.width - 20) / 6
                        spacing: 3
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.timeLabel(hour.modelData.time).replace(":00", "")
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overSurfaceVariant
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: hour.modelData.emoji
                            font.pixelSize: Styling.fontSize(2)
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.number(hour.modelData.temperature, "°")
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-1)
                            font.bold: true
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.number(hour.modelData.rainChance, "%")
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.primary
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            text: "Sunrise  " + root.timeLabel(WeatherService.sunrise)
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: "Sunset  " + root.timeLabel(WeatherService.sunset)
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }
    }
}
