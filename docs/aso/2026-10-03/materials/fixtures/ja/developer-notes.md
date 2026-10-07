# 開発ノート

コード・数式・図を使った小さな例。

## Swiftコード

```swift
let pages = [12, 18, 24]
let total = pages.reduce(0, +)
print("Read \(total) pages")
```

## 数式

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

## ワークフロー

```mermaid
flowchart LR
    A["開く"] --> B["読む"]
    B --> C["共有"]
```
