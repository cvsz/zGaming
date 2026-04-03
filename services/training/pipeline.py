import os

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier


def train(data_uri: str = "transactions.parquet", model_path: str = "model.pkl") -> None:
    # Placeholder source; production should use ClickHouse SQL export connector.
    df = pd.read_parquet(data_uri)

    X = df[["amount", "velocity", "balance", "fx_rate", "hour"]]
    y = df["fraud"]

    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X, y)

    os.makedirs(os.path.dirname(model_path) or ".", exist_ok=True)
    joblib.dump(model, model_path)


if __name__ == "__main__":
    train()
