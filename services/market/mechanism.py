"""Simple market mechanism with double-auction style matching."""


class Market:
    def __init__(self) -> None:
        self.orders: list[tuple[str, float, float]] = []

    def submit(self, agent_id: str, price: float, quantity: float) -> None:
        self.orders.append((agent_id, float(price), float(quantity)))

    def clear(self) -> list[tuple[str, str, float, float]]:
        self.orders.sort(key=lambda x: x[1])
        matched: list[tuple[str, str, float, float]] = []

        while len(self.orders) >= 2:
            buyer = self.orders.pop()
            seller = self.orders.pop(0)

            price = (buyer[1] + seller[1]) / 2
            qty = min(buyer[2], seller[2])
            if qty <= 0:
                continue

            matched.append((buyer[0], seller[0], price, qty))

        return matched
