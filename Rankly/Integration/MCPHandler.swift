import Foundation

/// Minimal MCP server (Streamable HTTP transport, JSON responses, no sessions) on POST /mcp.
/// Each tool maps onto a v1 endpoint so behaviour stays identical to the REST API.
@MainActor
final class MCPHandler {
    unowned let api: RanklyAPI
    init(api: RanklyAPI) { self.api = api }

    private struct Tool {
        let name: String
        let description: String
        let schema: [String: Any]
        let call: ([String: Any], HTTPRequest) -> HTTPRequest
    }

    private static func obj(_ props: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    private static let appProps: [String: [String: Any]] = [
        "appId": ["type": "string", "description": "App Store ID (trackId)"],
        "bundleId": ["type": "string", "description": "Bundle identifier, alternative to appId"],
    ]

    private lazy var tools: [Tool] = [
        Tool(name: "list_apps", description: "List the apps tracked in Rankly (your apps and competitors) with keyword counts and countries.",
             schema: Self.obj([:])) { _, base in Self.req(base, "GET", "/v1/apps") },
        Tool(name: "get_keywords",
             description: "Tracked keywords of an app with current App Store search rank, change since yesterday, estimated popularity (0–100), difficulty (0–100) and daily rank history.",
             schema: Self.obj(Self.appProps.merging(["country": ["type": "string", "description": "Two-letter App Store country, e.g. us"]]) { a, _ in a })) { a, base in
                 Self.req(base, "GET", "/v1/keywords", query: Self.strings(a, ["appId", "bundleId", "country"]))
             },
        Tool(name: "get_analysis",
             description: "Latest ASO analysis of an app in one country: keywords it ranks for, name/subtitle terms it doesn't rank for, competitors found automatically, opportunity keywords and a suggested 100-character keyword field.",
             schema: Self.obj(Self.appProps.merging(["country": ["type": "string"]]) { a, _ in a }, required: ["country"])) { a, base in
                 Self.req(base, "GET", "/v1/analysis", query: Self.strings(a, ["appId", "bundleId", "country"]))
             },
        Tool(name: "list_analyses", description: "Countries that have a saved analysis for an app, with summary counts.",
             schema: Self.obj(Self.appProps)) { a, base in
                 Self.req(base, "GET", "/v1/analysis/countries", query: Self.strings(a, ["appId", "bundleId"]))
             },
        Tool(name: "run_analysis",
             description: "Start an ASO analysis for one or more countries (runs in the background, ~1–3 min per country; poll analysis_status).",
             schema: Self.obj(Self.appProps.merging(["countries": ["type": "array", "items": ["type": "string"]]]) { a, _ in a }, required: ["countries"])) { a, base in
                 Self.req(base, "POST", "/v1/analysis", body: a)
             },
        Tool(name: "analysis_status", description: "Progress of running analyses for an app.",
             schema: Self.obj(Self.appProps)) { a, base in
                 Self.req(base, "GET", "/v1/analysis/status", query: Self.strings(a, ["appId", "bundleId"]))
             },
        Tool(name: "track_keywords", description: "Add keywords to Rankly's daily rank tracking for an app in a country (adds the app if needed).",
             schema: Self.obj(Self.appProps.merging(["country": ["type": "string"], "terms": ["type": "array", "items": ["type": "string"]]]) { a, _ in a },
                              required: ["country", "terms"])) { a, base in
                 Self.req(base, "POST", "/v1/keywords", body: a)
             },
        Tool(name: "check_ranks",
             description: "Live App Store search rank of an app for up to 60 terms in one country (paced and cached by Rankly).",
             schema: Self.obj(Self.appProps.merging(["country": ["type": "string"], "terms": ["type": "array", "items": ["type": "string"]]]) { a, _ in a },
                              required: ["country", "terms"])) { a, base in
                 Self.req(base, "POST", "/v1/ranks", body: a)
             },
        Tool(name: "add_event", description: "Mark a dated event (e.g. a metadata release) on an app's rank timeline.",
             schema: Self.obj(Self.appProps.merging(["note": ["type": "string"], "kind": ["type": "string", "enum": ["release", "note"]]]) { a, _ in a },
                              required: ["note"])) { a, base in
                 Self.req(base, "POST", "/v1/events", body: a)
             },
    ]

    private static func strings(_ a: [String: Any], _ keys: [String]) -> [String: String] {
        var q: [String: String] = [:]
        for k in keys { if let v = a[k] as? String { q[k] = v } }
        return q
    }

    private static func req(_ base: HTTPRequest, _ method: String, _ path: String,
                            query: [String: String] = [:], body: [String: Any]? = nil) -> HTTPRequest {
        let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return HTTPRequest(method: method, path: path, query: query, headers: base.headers, body: data)
    }

    // MARK: JSON-RPC

    func handle(_ req: HTTPRequest) async -> HTTPResponse {
        guard let msg = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let method = msg["method"] as? String else {
            return rpcError(id: nil, code: -32700, message: "Parse error")
        }
        let id = msg["id"]
        if id == nil { return .noContent }   // notifications (e.g. notifications/initialized)
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return rpcResult(id: id, [
                "protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "rankly", "version": RanklyAPI.appVersion],
                "instructions": "Rankly tracks real App Store search ranks for iPhone apps. Use list_apps to find appIds, then get_keywords or get_analysis. Popularity is an estimate from App Store autocomplete, not Apple's Search Ads score.",
            ])
        case "ping":
            return rpcResult(id: id, [:])
        case "tools/list":
            return rpcResult(id: id, ["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return rpcError(id: id, code: -32602, message: "Unknown tool")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let res = await api.route(tool.call(args, req))
            let text = String(data: res.body, encoding: .utf8) ?? ""
            return rpcResult(id: id, ["content": [["type": "text", "text": text]], "isError": res.status >= 400])
        default:
            return rpcError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func rpcResult(id: Any?, _ result: [String: Any]) -> HTTPResponse {
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return HTTPResponse(status: 200, body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }

    private func rpcError(id: Any?, code: Int, message: String) -> HTTPResponse {
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
        return HTTPResponse(status: 200, body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }
}
