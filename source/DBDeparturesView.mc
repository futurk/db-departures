import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Communications;
import Toybox.Time;
import Toybox.System;
import Toybox.Lang;
import Toybox.PersistedContent;

class DBDeparturesView extends WatchUi.DataField {

    private const USER_AGENT = "DBDepartures/1.0.0 (https://github.com/futurk/DBDepartures; contact@example.com)";
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
        dc.drawText(width / 2, 5, Graphics.FONT_SMALL, "Transitous Departures", Graphics.TEXT_JUSTIFY_CENTER);

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
        var lat = null;
        var lon = null;
        
        if (info has :destination && info.destination != null) {
            var dest = info.destination;
            var location = dest.toDegrees();
            lat = (location as Array<Double>)[0];
            lon = (location as Array<Double>)[1];
        }

        // SIMULATOR MOCK: Defaults to Berlin Hbf if no destination is active
        if (lat == null || lon == null) {
            lat = 52.5251;
            lon = 13.3694;
        }

        mStatusMessage = "Fetching Transitous...";
        mLastFetchTime = now;
        
        fetchNearestStation(lat as Double, lon as Double);
    }

    private function fetchNearestStation(lat as Double, lon as Double) as Void {
        var url = "https://api.transitous.org/api/v1/reverse-geocode";
        
        var params = {
            "lat" => lat.toString(),
            "lon" => lon.toString()
        };
        
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {
                "User-Agent" => USER_AGENT
            }
        };

        Communications.makeWebRequest(url, params, options, method(:onStationReceived));
    }

    function onStationReceived(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (responseCode == 200 && data != null) {
            var rawData = data as Object;
            
            // Reverse-geocode returns a Dictionary object with the nearest stop details
            if (rawData instanceof Dictionary) {
                var stationDict = rawData as Dictionary;
                if (stationDict.hasKey("id")) {
                    var stationId = stationDict.get("id") as String;
                    
                    if (stationDict.hasKey("name") && stationDict.get("name") != null) {
                        mStationName = stationDict.get("name") as String;
                    }
                    
                    fetchDeparturesForStation(stationId);
                    return;
                }
            } 
            // Fallback if the endpoint returns an Array of nearest stops sorted by distance
            else if (rawData instanceof Array) {
                var arrayData = rawData as Array;
                if (arrayData.size() > 0) {
                    var nearestStation = arrayData[0] as Dictionary;
                    if (nearestStation.hasKey("id")) {
                        var stationId = nearestStation.get("id") as String;
                        if (nearestStation.hasKey("name") && nearestStation.get("name") != null) {
                            mStationName = nearestStation.get("name") as String;
                        }
                        
                        fetchDeparturesForStation(stationId);
                        return;
                    }
                }
            }
        }
        
        mStatusMessage = "Station Not Found";
        System.println("Reverse Geocode Error: " + responseCode);
    }

    private function fetchDeparturesForStation(stationId as String) as Void {
        var url = "https://api.transitous.org/api/v6/stoptimes";
        var params = {
            "stopId" => stationId,
            "n" => "3"
        };

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :headers => {
                "User-Agent" => USER_AGENT
            }
        };

        Communications.makeWebRequest(url, params, options, method(:onDeparturesReceived));
    }

    function onDeparturesReceived(responseCode as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (responseCode == 200 && data != null && data instanceof Dictionary) {
            mDepartures = [];
            
            var dictData = data as Dictionary;
            if (dictData.hasKey("stoptimes") && dictData.get("stoptimes") instanceof Array) {
                var departuresList = dictData.get("stoptimes") as Array;
                
                for (var i = 0; i < departuresList.size(); i++) {
                    var dep = departuresList[i] as Dictionary;
                    
                    var lineName = "Train";
                    if (dep.hasKey("line") && dep.get("line") != null) {
                        lineName = dep.get("line") as String;
                    } else if (dep.hasKey("displayName") && dep.get("displayName") != null) {
                        lineName = dep.get("displayName") as String;
                    }

                    var direction = "Unknown";
                    if (dep.hasKey("headsign") && dep.get("headsign") != null) {
                        direction = dep.get("headsign") as String;
                    } else if (dep.hasKey("direction") && dep.get("direction") != null) {
                        direction = dep.get("direction") as String;
                    }

                    var rawTime = "";
                    if (dep.hasKey("time") && dep.get("time") != null) {
                        rawTime = dep.get("time") as String;
                    } else if (dep.hasKey("scheduledTime") && dep.get("scheduledTime") != null) {
                        rawTime = dep.get("scheduledTime") as String;
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
            mStatusMessage = "Transitous Error (" + responseCode + ")";
            System.println("Departure Fetch Error: " + responseCode);
        }
    }
}