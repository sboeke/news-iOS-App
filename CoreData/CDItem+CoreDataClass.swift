//
//  CDItem+CoreDataClass.swift
//  CloudNews
//
//  Created by Peter Hedlund on 10/31/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//
//

import Foundation
import CoreData

@objc(CDItem)
public class CDItem: NSManagedObject, ItemProtocol {

    static private let entityName = "CDItem"
    
    static func all() -> [ItemProtocol]? {
        let request : NSFetchRequest<CDItem> = self.fetchRequest()
        let sortDescription = NSSortDescriptor(key: "id", ascending: false)
        request.sortDescriptors = [sortDescription]

        var itemList = [ItemProtocol]()
        do {
            let results  = try NewsData.mainThreadContext.fetch(request)
            for record in results {
                itemList.append(record)
            }
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        return itemList
    }

    static func items(feed: Int32) -> [ItemProtocol]? {
        let request : NSFetchRequest<CDItem> = self.fetchRequest()
        let sortDescription = NSSortDescriptor(key: "id", ascending: false)
        request.sortDescriptors = [sortDescription]
        let predicate = NSPredicate(format: "feedId == %d", feed)
        request.predicate = predicate

        var itemList = [ItemProtocol]()
        do {
            let results  = try NewsData.mainThreadContext.fetch(request)
            for record in results {
                itemList.append(record)
            }
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        return itemList
    }

    static func starredItems() -> [ItemProtocol]? {
        let request : NSFetchRequest<CDItem> = self.fetchRequest()
        let sortDescription = NSSortDescriptor(key: "id", ascending: false)
        request.sortDescriptors = [sortDescription]
        let predicate = NSPredicate(format: "starred == true")
        request.predicate = predicate
        
        var itemList = [ItemProtocol]()
        do {
            let results  = try NewsData.mainThreadContext.fetch(request)
            for record in results {
                itemList.append(record)
            }
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        return itemList
    }
    
    static func update(items: [ItemProtocol]) {
        NewsData.mainThreadContext.performAndWait {
            let request: NSFetchRequest<CDItem> = CDItem.fetchRequest()
            do {
                var newItemsCount = 0
                for item in items {
                    let predicate = NSPredicate(format: "id == %d", item.id)
                    request.predicate = predicate
                    let records = try NewsData.mainThreadContext.fetch(request)
                    if let existingRecord = records.first {
                        existingRecord.author = item.author
                        existingRecord.body = item.body
                        existingRecord.enclosureLink = item.enclosureLink
                        existingRecord.enclosureMime = item.enclosureMime
                        existingRecord.feedId = item.feedId
                        existingRecord.fingerprint = item.fingerprint
                        existingRecord.guid = item.guid
                        existingRecord.guidHash = item.guidHash
//                        existingRecord.id = item.id
                        existingRecord.lastModified = item.lastModified
                        existingRecord.pubDate = item.pubDate
                        existingRecord.starred = item.starred
                        existingRecord.title = item.title
                        existingRecord.unread = item.unread
                        existingRecord.url = item.url
                    } else {
                        let newRecord = NSEntityDescription.insertNewObject(forEntityName: CDItem.entityName, into: NewsData.mainThreadContext) as! CDItem
                        newRecord.author = item.author
                        newRecord.body = item.body
                        newRecord.enclosureLink = item.enclosureLink
                        newRecord.enclosureMime = item.enclosureMime
                        newRecord.feedId = item.feedId
                        newRecord.fingerprint = item.fingerprint
                        newRecord.guid = item.guid
                        newRecord.guidHash = item.guidHash
                        newRecord.id = item.id
                        newRecord.lastModified = item.lastModified
                        newRecord.pubDate = item.pubDate
                        newRecord.starred = item.starred
                        newRecord.title = item.title
                        newRecord.unread = item.unread
                        newRecord.url = item.url
                        newItemsCount += 1
                    }
                }
                try NewsData.mainThreadContext.save()
                if newItemsCount > 0 {
                    let notification = NSUserNotification()
                    notification.identifier = NSUUID().uuidString
                    notification.title = "CloudNews"
                    notification.subtitle = "Updates available"
                    notification.informativeText = "\(newItemsCount) new articles"
                    notification.soundName = NSUserNotificationDefaultSoundName
                    //                notification.contentImage = NSImage(contentsOfURL: NSURL(string: "https://placehold.it/300")!)
                    // Manually display the notification
                    let notificationCenter = NSUserNotificationCenter.default
                    notificationCenter.deliver(notification)
                }
            } catch let error as NSError {
                print("Could not fetch \(error), \(error.userInfo)")
            }
        }
    }

    static func lastModified() -> Int32 {
        var result: Int32 = 0
        let request : NSFetchRequest<CDItem> = self.fetchRequest()
        let sortDescriptor = NSSortDescriptor(key: "lastModified", ascending: false)
        request.sortDescriptors = [sortDescriptor]
        request.fetchLimit = 1
        do {
            let results  = try NewsData.mainThreadContext.fetch(request)
            result = Int32(results.first?.lastModified ?? Int32(0))
        } catch let error as NSError {
            print("Could not fetch \(error), \(error.userInfo)")
        }
        return result
    }
    
    static func unreadCount() -> Int {
        var result = 0
        let request : NSFetchRequest<CDItem> = self.fetchRequest()
        let predicate = NSPredicate(format: "unread == true")
        request.predicate = predicate
        if let count = try? NewsData.mainThreadContext.count(for: request) {
            result = count
        }
        return result
    }
}