// WordCardView.swift — 单词卡片：单词+音标自动朗读 → 翻面看释义+例句（例句可朗读）→
// 底部三按钮认识/模糊/不认识。父视图（VocabView）用 .id(word.persistentModelID) 保证换词时
// isFlipped 等内部状态自动重置，无需手动 onChange。
import SwiftUI
import AVFoundation

/// 朗读服务：持有 AVSpeechSynthesizer 为属性（局部变量会在朗读完成前被释放导致不出声）。
/// 非 @Observable，纯工具类；由持有者（VocabView）以 @State 保存以维持其生命周期。
@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String = "en-US") {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }
}

struct WordCardView: View {
    let word: CachedWord
    let speechService: SpeechService
    let onFeedback: (Feedback) -> Void

    @State private var isFlipped = false

    private var definitions: [Definition] {
        (try? JSONDecoder().decode([Definition].self, from: Data(word.definitionsJSON.utf8))) ?? []
    }

    private var examples: [Example] {
        (try? JSONDecoder().decode([Example].self, from: Data(word.examplesJSON.utf8))) ?? []
    }

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isFlipped {
                        definitionsSection
                        examplesSection
                    } else {
                        Button {
                            isFlipped = true
                        } label: {
                            Text("显示释义")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

            feedbackButtons
        }
        .task {
            // 进入卡片自动朗读一次；.task 随 .id(word.persistentModelID) 换词而重新触发。
            speechService.speak(word.word)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.largeTitle.bold())
                if let phonetic = word.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                speechService.speak(word.word)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
            }
            .accessibilityLabel("重播发音")
        }
        .frame(maxWidth: .infinity)
    }

    private var definitionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("释义").font(.headline)
            ForEach(Array(definitions.enumerated()), id: \.offset) { _, definition in
                VStack(alignment: .leading, spacing: 2) {
                    Text("[\(definition.pos)] \(definition.meaning)")
                        .font(.body)
                    if let example = definition.example, !example.isEmpty {
                        Text(example)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if definitions.isEmpty {
                Text("暂无释义").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("例句").font(.headline)
            ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(example.en)
                            .font(.body)
                        Button {
                            speechService.speak(example.en)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("朗读例句")
                    }
                    Text(example.cn)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if examples.isEmpty {
                Text("暂无例句").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var feedbackButtons: some View {
        HStack(spacing: 12) {
            feedbackButton(title: "不认识", color: .red, feedback: .unknown)
            feedbackButton(title: "模糊", color: .yellow, feedback: .fuzzy)
            feedbackButton(title: "认识", color: .green, feedback: .know)
        }
    }

    private func feedbackButton(title: String, color: Color, feedback: Feedback) -> some View {
        Button {
            onFeedback(feedback)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }
}
