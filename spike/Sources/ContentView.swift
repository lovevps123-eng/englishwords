// ContentView.swift — spike 测试界面：选句 → 跟读 → 逐词红绿高亮 + 得分
import SwiftUI

let sentences = [
    "The little boy decided to give it a try.",
    "Scientists have discovered a new species in the ocean.",
    "Although it was raining, they continued their journey.",
    "I would rather stay at home than go shopping.",
    "The environment we live in is changing rapidly.",
]

struct ContentView: View {
    @StateObject var rec = Recognizer()
    @State var index = 0

    var target: String { sentences[index] }
    var diff: [(word: String, hit: Bool)] { wordDiff(target: target, recognized: rec.transcript) }

    var body: some View {
        VStack(spacing: 24) {
            Picker("句子", selection: $index) {
                ForEach(sentences.indices, id: \.self) { Text("句 \($0 + 1)").tag($0) }
            }.pickerStyle(.segmented)

            // 逐词高亮：绿=读中，红=漏/错
            diff.reduce(Text("")) { acc, item in
                acc + Text(item.word + " ").foregroundColor(item.hit ? .green : .red)
            }
            .font(.title2)

            Text("识别结果：\(rec.transcript)").foregroundColor(.secondary)
            Text("得分：\(score(diff))").font(.largeTitle).bold()
            if let err = rec.errorMessage { Text(err).foregroundColor(.orange) }

            Button(rec.isRecording ? "停止" : "开始跟读") {
                rec.isRecording ? rec.stop() : rec.start()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
