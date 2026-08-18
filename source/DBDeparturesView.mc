using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.Communications;
using Toybox.Time;
using Toybox.System;

class DBDeparturesView extends WatchUi.DataField {

    private var mDepartures = [];
    private var mStatusMessage = "Searching Destination...";
    private var mLastFetchTime = 0;
    private var mStationName = "";

    function initialize() {
        DataField.initialize();
    }

    // Called automatically by the system to update the display
    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();

        // Title Header
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 5, Graphics.FONT_SMALL, "DB Departures", Graphics.TEXT_JUSTIFY_CENTER);

        // Check active route & fetch status
        checkAndFetchDepartures();

        // Render departure list or status message
        if (mDepartures.size() > 0) {
            var yPos = 35;
            
            if (mStationName.length() > 0) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(width / 2, yPos, Graphics.FONT_TINY, mStationName, Graphics.TEXT_JUSTIFY_CENTER);
                yPos += 25;
            }

            for (var i = 0; i < mDepartures.size() && i < 3; i++) {
                var item = mDepartures[i];
                var lineText = item["line"] + " -> " + item["direction"] + " (" + item["time"] + ")";
                
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(10, yPos, Graphics.FONT_XTINY, lineText, Graphics.TEXT_JUSTIFY_LEFT);
                yPos += 22;
            }
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_TINY, mStatusMessage, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function checkAndFetchDepartures() {
        var now = Time.now().value();
        
        // Rate-limit request: execute every 60 seconds max
        if (now - mLastFetchTime < 60) {
            return;
        }

        var info = Activity.getActivityInfo();
        
        // Grab destination from active navigation course
        if (info has :destination && info.destination != null) {
            var location = info.destination.toDegrees();
            var lat = location[0];
            var lon = location[1];

            mStatusMessage = "Fetching DB Data...";
            mLastFetchTime = now;
            
            // 1. First step: Query DB nearest station ID using coordinates
            fetchNearestStation(lat, lon);
        } else {
            mStatusMessage = "No Active Destination";
        }
    }

    private function fetchNearestStation(lat, lon) {
        var url = "https://v6.db.transport.rest/locations/nearby";
        var params = {
            "latitude" => lat.toString(),
            "longitude" => lon.toString(),
            "results" => "1",
            "stops" => "true",
            "poi" => "false"
        };
        
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, params, options, method(:onStationReceived));
    }

    function onStationReceived(responseCode, data) {
        if (responseCode == 200 && data != null && data.size() > 0) {
            var stationId = data[0]["id"];
            mStationName = data[0]["name"];
            
            // 2. Second step: Fetch upcoming train departures using station ID
            fetchDeparturesForStation(stationId);
        } else {
            mStatusMessage = "Station Not Found";
            System.println("Station Lookup Error: " + responseCode);
        }
    }

    private function fetchDeparturesForStation(stationId) {
        var url = "https://v6.db.transport.rest/stops/" + stationId + "/departures";
        var params = {
            "results" => "3",
            "duration" => "60",
            "remarks" => "false",
            "linesOfStops" => "false"
        };

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, params, options, method(:onDeparturesReceived));
    }

    function onDeparturesReceived(responseCode, data) {
        if (responseCode == 200 && data != null) {
            mDepartures = [];
            
            // Extract lightweight variables to prevent Memory Overflows
            var departuresList = data["departures"];
            if (departuresList != null) {
                for (var i = 0; i < departuresList.size(); i++) {
                    var dep = departuresList[i];
                    
                    var lineName = (dep["line"] != null && dep["line"]["name"] != null) ? dep["line"]["name"] : "Train";
                    var direction = (dep["direction"] != null) ? dep["direction"] : "Unknown";
                    var rawTime = (dep["when"] != null) ? dep["when"] : "";
                    
                    // Basic ISO timestamp truncation (e.g. 2026-08-18T16:45:00 -> 16:45)
                    var formattedTime = "";
                    if (rawTime.length() >= 16) {
                        formattedTime = rawTime.substring(11, 16);
                    }

                    mDepartures.add({
                        "line" => lineName,
                        "direction" => direction,
                        "time" => formattedTime
                    });
                }
            }
            
            if (mDepartures.size() == 0) {
                mStatusMessage = "No Trains Nearby";
            }
        } else {
            mStatusMessage = "DB Fetch Error (" + responseCode + ")";
            System.println("Departure Fetch Error: " + responseCode);
        }
    }
}