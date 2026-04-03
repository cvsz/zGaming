use ark_ff::Field;
use ark_relations::r1cs::{ConstraintSynthesizer, ConstraintSystemRef, SynthesisError};
use ark_std::vec::Vec;

#[derive(Clone)]
pub struct LinearModelCircuit<F: Field> {
    pub inputs: Vec<F>,
    pub weights: Vec<F>,
    pub output: F,
}

impl<F: Field> ConstraintSynthesizer<F> for LinearModelCircuit<F> {
    fn generate_constraints(self, _cs: ConstraintSystemRef<F>) -> Result<(), SynthesisError> {
        let mut acc = F::zero();
        for (x, w) in self.inputs.iter().zip(self.weights.iter()) {
            acc += *x * *w;
        }

        if acc != self.output {
            return Err(SynthesisError::Unsatisfiable);
        }

        Ok(())
    }
}

fn main() {
    println!("zkML SNARK circuit scaffold ready");
}
