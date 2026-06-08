import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { requiresGeeGearBridgeFirst, routeLocalGearIntent } from "./gear-intents.js";

describe("Gear intent routing", () => {
  it("routes explicit WeChat Channels download URLs to the WeChat Channels Gear", () => {
    const routed = routeLocalGearIntent("Download this WeChat Channels video https://weixin.qq.com/sph/AZJc5LQAbb.");

    assert.equal(requiresGeeGearBridgeFirst("Download this WeChat Channels video https://weixin.qq.com/sph/AZJc5LQAbb."), true);
    assert.equal(routed?.hostActions.length, 2);
    assert.deepEqual(routed?.hostActions[0]?.arguments, { gear_id: "wechat.channels" });
    assert.deepEqual(routed?.hostActions[1]?.arguments, {
      gear_id: "wechat.channels",
      capability_id: "wechat_channels.download",
      args: {
        url: "https://weixin.qq.com/sph/AZJc5LQAbb",
      },
    });
  });

  it("routes explicit WeChat Channels preview URLs to metadata when no download verb is present", () => {
    const routed = routeLocalGearIntent(
      "Inspect https://channels.weixin.qq.com/finder-preview/pages/sph?id=AZJc5LQAbb",
    );

    assert.equal(routed?.hostActions[1]?.arguments.capability_id, "wechat_channels.metadata");
  });

  it("routes explicit Douyin download URLs to SmartYT download_now", () => {
    const routed = routeLocalGearIntent("Download this Douyin video https://v.douyin.com/iAbCdEfG/.");

    assert.equal(requiresGeeGearBridgeFirst("Download this Douyin video https://v.douyin.com/iAbCdEfG/."), true);
    assert.deepEqual(routed?.hostActions[0]?.arguments, { gear_id: "smartyt.media" });
    assert.deepEqual(routed?.hostActions[1]?.arguments, {
      gear_id: "smartyt.media",
      capability_id: "smartyt.download_now",
      args: {
        url: "https://v.douyin.com/iAbCdEfG/",
        download_kind: "video",
      },
    });
  });

  it("routes Xiaohongshu search requests to SmartYT candidate search", () => {
    const routed = routeLocalGearIntent("Search Xiaohongshu city night scene 3 results");

    assert.equal(requiresGeeGearBridgeFirst("Search Xiaohongshu city night scene 3 results"), true);
    assert.deepEqual(routed?.hostActions[1]?.arguments, {
      gear_id: "smartyt.media",
      capability_id: "smartyt.search_candidates",
      args: {
        query: "city night scene",
        platforms: ["xiaohongshu"],
        limit: 3,
      },
    });
  });
});
