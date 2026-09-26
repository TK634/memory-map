import SwiftUI
import UIKit

/// 日本語入力(ローマ字・かな)に強いテキスト欄。
///
/// SwiftUI の TextField は変換中(未確定)の文字もその都度バインディングに流すため、
/// 入力のたびに検索や保存が走ると画面が描き直され、変換中の文字が
/// 途中で確定したり消えたりする。
/// この欄は変換が確定したとき(markedTextRange が空のとき)だけ値を伝える。
struct IMETextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont = .rounded(17, .semibold)
    var textColor: UIColor = UIColor(AppPalette.chrome)
    var returnKey: UIReturnKeyType = .done
    /// 表示されたらすぐキーボードを出す
    var autoFocus = false
    /// リターンキーを押したとき
    var onCommit: () -> Void = {}

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = font
        tf.textColor = textColor
        tf.returnKeyType = returnKey
        tf.delegate = context.coordinator
        tf.text = text
        tf.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                     for: .editingChanged)
        // SwiftUI 側の幅に合わせて伸び縮みさせる
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tf.becomeFirstResponder() }
        }
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        // 変換中は外から書き換えない(ここで上書きすると未確定の文字が消える)
        if tf.markedTextRange == nil, tf.text != text {
            tf.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: IMETextField
        init(_ parent: IMETextField) { self.parent = parent }

        @objc func changed(_ tf: UITextField) {
            // 変換が確定したときだけ反映する
            guard tf.markedTextRange == nil else { return }
            let t = tf.text ?? ""
            if parent.text != t { parent.text = t }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            let t = tf.text ?? ""
            if parent.text != t { parent.text = t }
            parent.onCommit()
            return true
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            let t = tf.text ?? ""
            if parent.text != t { parent.text = t }
        }
    }
}

extension UIFont {
    /// 丸ゴシック体(SF Pro Rounded)
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

extension UIApplication {
    /// キーボードを閉じる
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
