#!/usr/bin/env python3
# 鸿蒙 UI 布局辅助：从 uitest dumpLayout 的 JSON 中查找文本与坐标。
# 用法：python3 harmony-ui-helper.py <layout.json> find <text> [<ymin> <ymax>]
#       python3 harmony-ui-helper.py <layout.json> find-id <id>
#       python3 harmony-ui-helper.py <layout.json> attr-id <id> <attribute>
import json, re, sys


def walk(node, out):
    attrs = node.get('attributes', {})
    text = attrs.get('text', '')
    bounds = attrs.get('bounds', '')
    if text:
        out.append((text, bounds))
    for child in node.get('children', []):
        walk(child, out)


def walk_attributes(node, out):
    attrs = node.get('attributes', {})
    out.append(attrs)
    for child in node.get('children', []):
        walk_attributes(child, out)


def parse_bounds(value):
    # [x1,y1][x2,y2]
    nums = re.findall(r'\d+', value)
    if len(nums) < 4:
        return None
    try:
        return int(nums[0]), int(nums[1]), int(nums[2]), int(nums[3])
    except ValueError:
        return None


def main():
    path = sys.argv[1]
    command = sys.argv[2]
    needle = sys.argv[3]
    data = json.loads(open(path, encoding='utf-8').read())
    if command in ('find-id', 'attr-id'):
        nodes = []
        walk_attributes(data, nodes)
        for attrs in nodes:
            if attrs.get('id', '') != needle:
                continue
            if command == 'attr-id':
                attribute = sys.argv[4]
                print(attrs.get(attribute, ''))
                return
            parsed = parse_bounds(attrs.get('bounds', ''))
            if parsed is not None:
                print(*parsed)
                return
        sys.exit(1)

    ymin = int(sys.argv[4]) if len(sys.argv) > 4 else -1
    ymax = int(sys.argv[5]) if len(sys.argv) > 5 else 10 ** 9
    found = []
    walk(data, found)
    for text, bounds in found:
        if text != needle:
            continue
        parsed = parse_bounds(bounds)
        if parsed is None:
            continue
        x1, y1, x2, y2 = parsed
        if y1 >= ymin and y1 <= ymax:
            print(x1, y1, x2, y2)
            return
    sys.exit(1)


if __name__ == '__main__':
    main()
