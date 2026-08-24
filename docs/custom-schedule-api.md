# 自定义日程接口 / Custom schedule feed API

Where To Study `0.2.5` 起允许用户在设置中填写一个自定义日程 JSON 地址。该接口用于补充
教学日历中的全天截止日程，不会替换个人课表、云课堂作业或内置竞赛来源。

Starting with Where To Study `0.2.5`, users may configure one custom JSON schedule feed.
The feed adds all-day deadline entries to the teaching calendar and does not replace the
personal timetable, UCloud assignments, or built-in contest sources.

## 请求约束 / Request requirements

- 地址必须是公开可访问的 `https://` URL，不得包含用户名或密码。
- 客户端只发送不带凭据、Cookie、课表或设备标识的 `GET`，并声明接受 JSON。
- 客户端拒绝 HTTP 重定向、`localhost`、`.localhost` 与私有/保留 IP 字面量。
- 响应体上限为 2 MiB；单日最多接收 100 项，单次日历范围最多 370 天。
- 客户端可缓存成功响应 5 分钟。关闭自定义源后不再展示普通条目，但已收藏的完整事件快照仍保留。

- The URL must be a publicly reachable `https://` endpoint without embedded credentials.
- Clients issue a credential-free `GET` with no cookies, timetable data, or device identifier.
- Redirects, `localhost`, `.localhost`, and literal private/reserved IP addresses are rejected.
- Responses are limited to 2 MiB, 100 accepted items per day, and a 370-day calendar range.
- A successful response may be cached for five minutes. Disabling the feed hides ordinary
  entries, while complete snapshots of favorited entries remain available locally.

## JSON 格式 / JSON format

正式 JSON Schema 位于
[`contracts/v1/custom-deadline-feed.schema.json`](../contracts/v1/custom-deadline-feed.schema.json)，
完整虚构示例位于
[`contracts/v1/fixtures/custom-deadline-feed.json`](../contracts/v1/fixtures/custom-deadline-feed.json)。

```json
{
  "version": 1,
  "source": "My Schedule",
  "homepage": "https://example.com/calendar",
  "updated_at": "2026-08-24T08:00:00+08:00",
  "items": [
    {
      "id": "registration-2026",
      "name": "Registration deadline",
      "event_type": "custom",
      "primary_deadline": "2026-09-18T23:59:00+08:00",
      "organizer": "Example organizer",
      "official_url": "https://example.com/calendar/registration-2026"
    }
  ]
}
```

字段说明 / Fields:

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `version` | 是 | 当前固定为整数 `1`。 |
| `source` | 是 | 来源名称，1–80 个字符；显示在第三方来源声明中。 |
| `homepage` | 否 | 来源主页，只接受 HTTPS。 |
| `updated_at` | 否 | 带时区的 RFC 3339 更新时间。 |
| `items[].id` | 是 | 来源内稳定 ID，1–128 个字符。相同 `id` 与时间戳视为同一条目。 |
| `items[].name` | 是 | 日程名称，1–200 个字符。API 原文不会随界面语言翻译。 |
| `items[].event_type` | 是 | `competition`、`summer_camp`、`hackathon` 或 `custom`。 |
| `items[].primary_deadline` | 是 | 必须包含时区的 RFC 3339 时间戳；客户端按其前十位日期放入全天区，并在详情中保留时间。 |
| `items[].organizer` | 否 | 组织方，1–200 个字符。 |
| `items[].official_url` | 否 | 日程原文链接，只接受 HTTPS。 |

The API payload is treated as untrusted input. Invalid envelopes fail the feed request;
individual entries with blank IDs/names, unsupported types, invalid timestamps, or unsafe
links are ignored. Consumers should keep IDs stable and include an explicit UTC offset in every
`primary_deadline`.

## 收藏与失效 / Favorites and disappearance

收藏时客户端会在本地保存完整条目（ID、名称、类型、来源、时间、组织方与安全原文链接）。
因此来源关闭、请求失败或上游删除条目后，收藏仍会显示在原日期；取消收藏才会删除本地快照。
收藏不会上传或在设备间同步，清除应用本地数据会一并清除。

Favoriting stores the complete entry snapshot locally. A favorite therefore stays on its original
date if the feed is disabled, unavailable, or no longer contains the item. Favorites are never
uploaded or synchronized between devices and are removed by the app's local-data reset.
