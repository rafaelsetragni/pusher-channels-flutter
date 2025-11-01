import Flutter
import Foundation
import PusherSwift
import UIKit

public class SwiftPusherChannelsFlutterPlugin: NSObject, FlutterPlugin, PusherDelegate, Authorizer {
  private var pusher: Pusher?
  public var methodChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftPusherChannelsFlutterPlugin()
    instance.methodChannel = FlutterMethodChannel(name: "pusher_channels_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      initChannels(call: call, result: result)
    case "connect":
      connect(result: result)
    case "disconnect":
      disconnect(result: result)
    case "getSocketId":
      getSocketId(result: result)
    case "subscribe":
      subscribe(call: call, result: result)
    case "unsubscribe":
      unsubscribe(call: call, result: result)
    case "trigger":
      trigger(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func initChannels(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if let existingPusher = pusher {
        existingPusher.disconnect()
    }
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "Arguments are not a valid dictionary", details: nil))
      return
    }
    var authMethod: AuthMethod = .noMethod
    if let authEndpoint = args["authEndpoint"] as? String {
      authMethod = .endpoint(authEndpoint: authEndpoint)
    } else if let authorizer = args["authorizer"] as? Bool, authorizer == true {
      authMethod = .authorizer(authorizer: self)
    }
    var customHost: String?
    if let hostArg = args["host"] as? String {
        customHost = hostArg
    }
    var host: PusherHost = .defaultHost
    if let customHost = customHost {
        host = .host(customHost)
    } else if let cluster = args["cluster"] as? String {
        host = .cluster(cluster)
    }
    var useTLS: Bool = true
    if let useTLSArg = args["useTLS"] as? Bool {
      useTLS = useTLSArg
    }
    var port: Int
    if useTLS {
      port = 443
      if let wssPort = args["wssPort"] as? Int {
        port = wssPort
      }
    } else {
      port = 80
      if let wsPort = args["wsPort"] as? Int {
        port = wsPort
      }
    }
    var activityTimeout: TimeInterval?
    if let activityTimeoutArg = args["activityTimeout"] as? TimeInterval {
      activityTimeout = activityTimeoutArg / 1000.0
    }
    var path: String?
    if let pathArg = args["path"] as? String {
      path = pathArg
    }
    let allowSelfSigned = args["allowSelfSigned"] as? Bool ?? false
    guard let apiKey = args["apiKey"] as? String else {
      result(FlutterError(code: "missing_api_key", message: "Missing or invalid API key", details: nil))
      return
    }
    let options = PusherClientOptions(
      authMethod: authMethod,
      host: host,
      port: port,
      path: path,
      useTLS: useTLS,
      activityTimeout: activityTimeout
    )
    let pusher = Pusher(key: apiKey, options: options)

    if let maxReconnectionAttempts = args["maxReconnectionAttempts"] as? Int {
      pusher.connection.reconnectAttemptsMax = maxReconnectionAttempts
    }
    if let maxReconnectGapInSeconds = args["maxReconnectGapInSeconds"] as? TimeInterval {
      pusher.connection.maxReconnectGapInSeconds = maxReconnectGapInSeconds
    }
    if let pongTimeout = args["pongTimeout"] as? Int {
      pusher.connection.pongResponseTimeoutInterval = TimeInterval(pongTimeout) / 1000.0
    }
    pusher.connection.delegate = self
    pusher.bind(eventCallback: onEvent)
    self.pusher = pusher
    result(nil)
  }

  public func fetchAuthValue(socketID: String, channelName: String, completionHandler: @escaping (PusherAuth?) -> Void) {
    guard let methodChannel = methodChannel else {
      completionHandler(nil)
      return
    }
    methodChannel.invokeMethod("onAuthorizer", arguments: [
      "socketId": socketID,
      "channelName": channelName,
    ]) { authData in
      if let authDataCast = authData as? [String: String] {
        completionHandler(
          PusherAuth(
            auth: authDataCast["auth"] ?? "",
            channelData: authDataCast["channel_data"],
            sharedSecret: authDataCast["shared_secret"]
          ))
      } else {
        completionHandler(nil)
      }
    }
  }

  public func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
    methodChannel?.invokeMethod("onConnectionStateChange", arguments: [
      "previousState": old.stringValue(),
      "currentState": new.stringValue(),
    ])
  }

  public func debugLog(message _: String) {
    // print("DEBUG:", message)
  }

  public func subscribedToChannel(name _: String) {
    // Handled by global handler
  }

  public func failedToSubscribeToChannel(name _: String, response _: URLResponse?, data _: String?, error: NSError?) {
    methodChannel?.invokeMethod(
      "onSubscriptionError", arguments: [
        "message": error?.localizedDescription ?? "",
        "error": error?.debugDescription ?? "",
      ]
    )
  }

  public func receivedError(error: PusherError) {
    methodChannel?.invokeMethod(
      "onError", arguments: [
        "message": error.message,
        "code": error.code ?? -1,
        "error": error.debugDescription,
      ]
    )
  }

  public func failedToDecryptEvent(eventName: String, channelName _: String, data: String?) {
    methodChannel?.invokeMethod(
      "onDecryptionFailure", arguments: [
        "eventName": eventName,
        "reason": data as Any,
      ]
    )
  }

  func connect(result: @escaping FlutterResult) {
    guard let pusher = pusher else {
      result(FlutterError(code: "not_initialized", message: "Pusher client is not initialized", details: nil))
      return
    }
    pusher.connect()
    result(nil)	
  }

  func disconnect(result: @escaping FlutterResult) {
    guard let pusher = pusher else {
      result(FlutterError(code: "not_initialized", message: "Pusher client is not initialized", details: nil))
      return
    }
    pusher.disconnect()
    result(nil)
  }

  func getSocketId(result: @escaping FlutterResult) {
    guard let pusher = pusher else {
      result(nil)
      return
    }
    result(pusher.connection.socketId ?? "")
  }

  func onEvent(event: PusherEvent) {
    guard let methodChannel = methodChannel else {
      return
    }
    var userId: String?
    if event.eventName == "pusher:subscription_succeeded" {
      if let channelName = event.channelName,
         let pusher = pusher,
         let channel = pusher.connection.channels.findPresence(name: channelName) {
        userId = channel.myId
      }
    }
    methodChannel.invokeMethod(
      "onEvent", arguments: [
        "channelName": event.channelName ?? "",
        "eventName": event.eventName,
        "userId": event.userId ?? userId,
        "data": event.data as Any,
      ]
    )
  }

  func subscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let pusher = pusher else {
      result(FlutterError(code: "not_initialized", message: "Pusher client is not initialized", details: nil))
      return
    }
    guard let args = call.arguments as? [String: String],
          let channelName = args["channelName"] else {
      result(FlutterError(code: "invalid_arguments", message: "Missing or invalid channelName", details: nil))
      return
    }
    if channelName.hasPrefix("presence-") {
      let onMemberAdded: (PusherPresenceChannelMember) -> Void = { user in
        self.methodChannel?.invokeMethod("onMemberAdded", arguments: [
          "channelName": channelName,
          "user": ["userId": user.userId, "userInfo": user.userInfo],
        ])
      }
      let onMemberRemoved: (PusherPresenceChannelMember) -> Void = { user in
        self.methodChannel?.invokeMethod("onMemberRemoved", arguments: [
          "channelName": channelName,
          "user": ["userId": user.userId, "userInfo": user.userInfo],
        ])
      }
      pusher.subscribeToPresenceChannel(
        channelName: channelName,
        onMemberAdded: onMemberAdded,
        onMemberRemoved: onMemberRemoved
      )
    } else {
      let onSubscriptionCount: (Int) -> Void = { subscriptionCount in
        self.methodChannel?.invokeMethod(
          "onEvent", arguments: [
            "channelName": channelName,
            "eventName": "pusher:subscription_count",
            "userId": nil,
            "data": [
              "subscription_count": subscriptionCount,
            ],
          ]
        )
      }
      pusher.subscribe(channelName: channelName,
                       onSubscriptionCountChanged: onSubscriptionCount)
    }
    result(nil)
  }

  func unsubscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let pusher = pusher else {
      result(FlutterError(code: "not_initialized", message: "Pusher client is not initialized", details: nil))
      return
    }
    guard let args = call.arguments as? [String: String],
          let channelName = args["channelName"] else {
      result(FlutterError(code: "invalid_arguments", message: "Missing or invalid channelName", details: nil))
      return
    }
    pusher.unsubscribe(channelName)
    result(nil)
  }

  func trigger(call: FlutterMethodCall, result _: @escaping FlutterResult) {
    guard let pusher = pusher else {
      return
    }
    guard let args = call.arguments as? [String: String],
          let channelName = args["channelName"],
          let eventName = args["eventName"] else {
      return
    }
    let data: String? = args["data"]
    if let channel = pusher.connection.channels.find(name: channelName) {
      channel.trigger(eventName: eventName, data: data as Any)
    }
  }
}
