import numpy as np
from sklearn.ensemble import RandomForestClassifier


class UpliftModel:
    def __init__(self) -> None:
        self.model_t = RandomForestClassifier(random_state=42)
        self.model_c = RandomForestClassifier(random_state=42)

    def fit(self, X: np.ndarray, treatment: np.ndarray, y: np.ndarray) -> None:
        self.model_t.fit(X[treatment == 1], y[treatment == 1])
        self.model_c.fit(X[treatment == 0], y[treatment == 0])

    def predict_uplift(self, X: np.ndarray) -> np.ndarray:
        p_t = self.model_t.predict_proba(X)[:, 1]
        p_c = self.model_c.predict_proba(X)[:, 1]
        return p_t - p_c
