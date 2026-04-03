use risc0_zkvm::guest::env;

pub fn run() {
    let input: Vec<u8> = env::read();
    let digest = risc0_zkvm::sha::sha256(&input);
    env::commit(&digest);
}
