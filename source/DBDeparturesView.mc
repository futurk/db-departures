import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Communications;
import Toybox.Time;
import Toybox.System;
import Toybox.Lang;
import Toybox.PersistedContent;

class DBDeparturesView extends WatchUi.DataField {

    private var mDepartures as Array<Dictionary> = [];
    private var mStatusMessage as String = "Searching Destination...";
    private var mLastFetchTime as Number = 0;
    private var mStationName as String = "";

    function initialize() {
        DataField.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();

        // Header Title
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 5, Graphics.FONT_SMALL, "DB Departures", Graphics.TEXT_JUSTIFY_CENTER);

        checkAndFetchDepartures();

        if (mDepartures.size() > 0) {
            var yPos = 35;
            
            if (mStationName.length() > 0) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(width / 2, yPos, Graphics.FONT_TINY, mStationName, Graphics.TEXT_JUSTIFY_CENTER);
                yPos += 25;
            }

            for (var i = 0; i < mDepartures.size() && i < 3; i++) {
                var item = mDepartures[i] as Dictionary;
                var lineVal = item.get("line") as String;
                var dirVal = item.get("direction") as String;
                var timeVal = item.get("time") as String;
                
                var lineText = lineVal + " -> " + dirVal + " (" + timeVal + ")";
                
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(10, yPos, Graphics.FONT_XTINY, lineText, Graphics.TEXT_JUSTIFY_LEFT);
                yPos += 22;
            }
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2, Graphics.FONT_TINY, mStatusMessage, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function checkAndFetchDepartures() as Void {
        var now = Time.now().value();
        
        if (now - mLastFetchTime < 60) {
            return;
        }

        var info = Activity.getActivityInfo();
        
        if (info has :destination && info.destination != null) {
            var dest = info.destination;
            if (dest != null) {
                var location = dest.toDegrees();
                var lat = (location as Array<Double>)[0];
                var lon = (location as Array<Double>)[1];

                mStatusMessage = "Fetching DB Data...";
                mLastFetchTime = now;
                
                fetchNearestStation(lat, lon);
            }
        } else {
            mStatusMessage = "No Active Destination";
        }
    }

    private function fetchNearestStation(lat as Double, lon as Double) as Void {
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

    // Fixed parameter type signature matching Garmin's strict web request requirement
    function onStationReceived(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
            if (responseCode == 200 && data != null) {
                // Cast to Object to allow type checking and casting to Array without compiler warnings
                var rawData = data as Object;
                if (rawData instanceof Array) {
                    var arrayData = rawData as Array;
                    if (arrayData.size() > 0) {
                        var firstStation = arrayData[0] as Dictionary;
                        var stationId = firstStation.get("id") as String;
                        mStationName = firstStation.get("name") as String;
                        
                        fetchDeparturesForStation(stationId);
                        return;
                    }
                }
            }
            mStatusMessage = "Station Not Found";
            System.println("Station Lookup Error: " + responseCode);
        }

    private function fetchDeparturesForStation(stationId as String) as Void {
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

    // Fixed parameter type signature matching Garmin's strict web request requirement
    function onDeparturesReceived(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            mDepartures = [];
            
            var dictData = data as Dictionary;
            if (dictData.hasKey("departures") && dictData.get("departures") instanceof Array) {
                var departuresList = dictData.get("departures") as Array;
                
                for (var i = 0; i < departuresList.size(); i++) {
                    var dep = departuresList[i] as Dictionary;
                    
                    var lineName = "Train";
                    if (dep.hasKey("line") && dep.get("line") instanceof Dictionary) {
                        var lineDict = dep.get("line") as Dictionary;
                        if (lineDict.hasKey("name") && lineDict.get("name") != null) {
                            lineName = lineDict.get("name") as String;
                        }
                    }

                    var direction = "Unknown";
                    if (dep.hasKey("direction") && dep.get("direction") != null) {
                        direction = dep.get("direction") as String;
                    }

                    var rawTime = "";
                    if (dep.hasKey("when") && dep.get("when") != null) {
                        rawTime = dep.get("when") as String;
                    }
                    
                    var formattedTime = "";
                    if (rawTime.length() >= 16) {
                        formattedTime = rawTime.substring(11, 16);
                    }

                    var item = {
                        "line" => lineName,
                        "direction" => direction,
                        "time" => formattedTime
                    };

                    mDepartures.add(item);
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