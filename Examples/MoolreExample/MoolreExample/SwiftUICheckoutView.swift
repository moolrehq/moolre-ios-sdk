import MoolreSwiftUI
import SwiftUI

private struct SampleProduct: Identifiable {
    let id = UUID()
    let name: String
    let price: Decimal
}

/// SwiftUI checkout using the branded `MoolrePayButton`.
struct SwiftUICheckoutView: View {
    private let config = SampleConfig.make(redirectURL: "moolre-example://payment-callback")
    private let sampleProductNames = ["Smart Watch", "USB Charger", "Gaming Mouse", "LED Bulb", "Water Bottle", "Backpack"]

    @State private var products = [
        SampleProduct(name: "Wireless Headphones", price: Decimal(string: "0.50")!),
        SampleProduct(name: "Bluetooth Speaker", price: Decimal(string: "0.20")!)
    ]
    @State private var paymentResult: MoolrePaymentResult?

    private var totalAmount: Decimal {
        products.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Cart") {
                    ForEach(products) { product in
                        HStack {
                            Text(product.name)
                            Spacer()
                            Text(formatGHS(product.price)).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { products.remove(atOffsets: $0) }

                    Button {
                        let cents = Int.random(in: 10...110)
                        products.append(SampleProduct(
                            name: sampleProductNames.randomElement()!,
                            price: Decimal(cents) / 100
                        ))
                    } label: {
                        Label("Add random item", systemImage: "plus")
                    }
                }

                Section {
                    HStack {
                        Text("Total").font(.title3.bold())
                        Spacer()
                        Text(formatGHS(totalAmount)).font(.title3.bold())
                    }

                    switch config {
                    case .success(let config):
                        MoolrePayButton(
                            config: config,
                            payment: MoolrePaymentRequest(amount: totalAmount, currency: "GHS", email: "customer@example.com"),
                            showAmount: true,
                            onResult: { paymentResult = $0 }
                        )
                        .disabled(totalAmount <= 0)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    case .failure(let error):
                        Text("Sample credentials are invalid: \(error.message)")
                            .foregroundColor(.red)
                    }
                } footer: {
                    Text("This demo uses the same payment flow as the UIKit sample.")
                }

                if let paymentResult {
                    Section("Result") {
                        Text(paymentResult.displayText)
                    }
                }
            }
            .navigationTitle("Moolre Checkout")
        }
        .navigationViewStyle(.stack)
        .moolreTheme()
    }
}
