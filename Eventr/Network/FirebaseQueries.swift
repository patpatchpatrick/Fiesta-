//
//  FirebaseQueries.swift
//  Eventr
//
//  Created by Patrick Doyle on 5/28/19.
//  Copyright © 2019 Patrick Doyle. All rights reserved.
//

import Foundation
import Firebase
import GeoFire
import MapKit

//Class to track types of queries that can be performed in Firebase

var gQuery : GFCircleQuery?

//Query all upcoming events using the dates input by the user
func queryUpcomingEvents(city: String, firstPage: Bool){
    
    let beforeDate = Double((Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: fromDate)?.convertToTimeZone(initTimeZone: Calendar.current.timeZone, timeZone: TimeZone(secondsFromGMT: 0)!).timeIntervalSince1970)!)
    let afterDate = ((Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: toDate)?.convertToTimeZone(initTimeZone: Calendar.current.timeZone, timeZone: TimeZone(secondsFromGMT: 0)!).timeIntervalSince1970)!)
    
    if firstPage{
        //First page query
        
        //Reset query variables and clear tableview when a new search has begun
        tableEvents.removeAll()
        allEvents.removeAll()
        mostRecentlyQueriedDate = nil
        paginationInProgress = false
        
        //Query all events between the before and after date selected by the user
        //Events are sorted by date in ascending order using "dateSort", which is equal to "0 - date" since Firebase can only sort in descending order
        firebaseDatabaseRef.child("events").child(city).queryOrdered(byChild: "dateSort").queryStarting(atValue: 0 - afterDate).queryEnding(atValue: 0 - beforeDate).queryLimited(toLast: paginationFirstPageCount).observeSingleEvent(of: .value, with: {
            (snapshot) in
            guard let dict = snapshot.value as? NSDictionary else { return }
            addQueriedEventsToTableView(eventsList: dict)
        })
        
    } else {
        //Query for another page
        //If the all events count is greater than the initial query amount, then more events are ready to be loaded
        if (allEvents.count >= paginationFirstPageCount) {
            
            if let lastDateValue = mostRecentlyQueriedDate?.timeIntervalSince1970 {
                
                //The queryStartValue is exactly 1 second more than the last queried value's date.  This is done so that no duplicates are added to the list of queried values
                let queryStartValue = 0 - lastDateValue - 1
                
                //Query all events between the most recently queried date and the after date selected by the user
                //Events are sorted by date in ascending order using "dateSort", which is equal to "0 - date" since Firebase can only sort in descending order
                firebaseDatabaseRef.child("events").child(city).queryOrdered(byChild: "dateSort").queryStarting(atValue: 0 - afterDate ).queryEnding(atValue: queryStartValue).queryLimited(toLast: paginationAddlPageCount).observeSingleEvent(of: .value, with: {
                    (snapshot) in
                    guard let dict = snapshot.value as? NSDictionary else { return }
                    addQueriedEventsToTableView(eventsList: dict)
                })
                
            }
        }
        
    }
    
}

//Query all events by popularity (upvote count)
func queryPopularEvents(city: String, firstPage: Bool){
    
    if firstPage{
        //First page query
        
        //Reset query variables and clear tableview when a new search has begun
        tableEvents.removeAll()
        allEvents.removeAll()
        mostRecentlyQueriedUpvoteCount = nil
        paginationInProgress = false
        
        //Query all events between the before and after date selected by the user
        //Events are sorted by date in ascending order using "dateSort", which is equal to "0 - date" since Firebase can only sort in descending order
        firebaseDatabaseRef.child("events").child(city).queryOrdered(byChild: "upvotes").queryLimited(toLast: paginationFirstPageCount).observeSingleEvent(of: .value, with: {
            (snapshot) in
            guard let dict = snapshot.value as? NSDictionary else { return }
            addQueriedEventsToTableView(eventsList: dict)
        })
        
    } else {
        //Query for another page
        //If the all events count is greater than the initial query amount, then more events are ready to be loaded
        if (allEvents.count >= paginationFirstPageCount) {
            
            if let lastUpvoteCount = mostRecentlyQueriedUpvoteCount {
                //The next page of events queried will start with an upvote count of 1 less than the most recently queried event.  This will ensure events are queried in order.
                
                //Query all events between the most recently queried date and the after date selected by the user
                //Events are sorted by date in ascending order using "dateSort", which is equal to "0 - date" since Firebase can only sort in descending order
                firebaseDatabaseRef.child("events").child(city).queryOrdered(byChild: "upvotes").queryEnding(atValue: lastUpvoteCount - 1).queryLimited(toLast: paginationAddlPageCount).observeSingleEvent(of: .value, with: {
                    (snapshot) in
                    guard let dict = snapshot.value as? NSDictionary else { return }
                    addQueriedEventsToTableView(eventsList: dict)
                })
            }
            
        }
        
    }
    
}

//Query list of events within a certain radius of a location
func queryNearbyEvents(centerLocation: CLLocation?, radius: Double){
    
    guard let queryLocation = centerLocation else {return}
    let searchDistanceKm = radius * 1.60934 //Convert radius(miles) to km
    
    tableEvents.removeAll()
    allEvents.removeAll()
    
    //Query to find all keys(event IDs) within radius of location
    //When new events are found, they are added to the tableView
    gQuery = geoFire.query(at: queryLocation, withRadius: searchDistanceKm)
    guard let gQ = gQuery else {return}
    gQ.observe(.keyEntered, with: { (key: String!, location: CLLocation!) in
        addEventsToEventTableViewByEventID(eventIDMap: [key as Any : "NYC"] as NSDictionary, isUserCreatedEvent: false, filterByCategory: true)
    })
    
    //Method called when the query is finished and all keys(event IDs) are loaded
    //After all events within a radius are loaded, check if the distance query is complete or if the radius needs to be increased
    gQ.observeReady {
        checkIfNearbyQueryIsComplete()
    }
    
}


//Query list of Firebase events that were favorited by the user and add them to the eventsTableView
func queryFirebaseFavoriteEvents(){
    
    guard let userID = Auth.auth().currentUser?.uid else { return }
    tableEvents.removeAll()
    firebaseDatabaseRef.child("favorited").child(userID).observeSingleEvent(of: .value, with: {
        (snapshot) in
        guard let dict = snapshot.value as? NSDictionary else { return }
        addEventsToEventTableViewByEventID(eventIDMap: dict, isUserCreatedEvent: false, filterByCategory: false)
    })
    
}

//Query list of Firebase events that were created by the user and add them to the eventsTableView
func queryFirebaseCreatedEvents(){
    
    guard let userID = Auth.auth().currentUser?.uid else { return }
    tableEvents.removeAll()
    firebaseDatabaseRef.child("created").child(userID).observeSingleEvent(of: .value, with: {
        (snapshot) in
        guard let dict = snapshot.value as? NSDictionary else { return }
        addEventsToEventTableViewByEventID(eventIDMap: dict, isUserCreatedEvent: true, filterByCategory: false)
    })
    
}

//Check to see if the event is marked as upvoted in firebase and update the event data and tableview accordingly
func queryIfFirebaseEventIsUpvoted(event: Event){
    
    guard let userID = Auth.auth().currentUser?.uid else { return }
    
    firebaseDatabaseRef.child("users").child(userID).child("upvoted").observeSingleEvent(of: .value, with: {
        (snapshot) in
        guard let dict = snapshot.value as? NSDictionary else { return }
        _ = dict.allValues.contains { element in
            if case element as! String = event.id {
                event.upvoted = true
                reloadEventTableView()
                return true
            } else {
                event.upvoted = false
                reloadEventTableView()
                return false
            }
        }
    })
    
}

func queryIfUserIsAttendingEvent(event: Event) {
    
    guard let userID = Auth.auth().currentUser?.uid else { return }
    
    //Check if event is being attended by user.  If so, reload the event view controller to reflect this
    firebaseDatabaseRef.child("attendingUsers").child(userID).observeSingleEvent(of: .value, with: {
        (snapshot) in
        var userIsAttendingEvent = false
        let dict = snapshot.value as? NSDictionary
        if dict != nil {
            userIsAttendingEvent = dict!.allValues.contains { element in
                if case element as! String = event.id { return true } else { return false }
            }
        }
        
        if userIsAttendingEvent {
            selectedEvent.loggedInUserAttendingTheEvent = true
            reloadEventViewController()
        }
        
    })
    
}


//Query a firebase event to determine if it was favorited
func queryIfFirebaseEventIsFavorited(event: Event){
    
    guard let userID = Auth.auth().currentUser?.uid else { return }
    
    //Check if event has already been favorited
    //An event has already been favorited if the "favorite/userID" section of firebase contains the eventID as a key
    firebaseDatabaseRef.child("favorited").child(userID).observeSingleEvent(of: .value, with: {
        (snapshot) in
        guard let dict = snapshot.value as? NSDictionary else { return }
        let eventAlreadyFavorited = dict.allKeys.contains { element in
            if case element as! String = event.id { return true } else { return false }
        }
        
        //If event was marked as favorite, set the event's favorited variable to true
        if eventAlreadyFavorited {
            event.favorite = true
            reloadEventTableView()
        }
        
    })
    
    
    
}
