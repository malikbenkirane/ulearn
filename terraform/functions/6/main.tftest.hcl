run "hash_test" {

  command = plan

  variables {
    expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    // obtained = output.filesha256 // to illustrate "Unknown condition run" error
  }

  // "Error: Unknown condition run: Condition could not be evaluated at this time"
  //
  // assert {
  //   condition     = var.expected != var.obtained
  //   error_message = "variable assignment precedes plan/apply"
  // }

  assert {
    condition     = var.expected == output.filesha256
    error_message = "unexpected filesha256"
  }

  assert {
    condition     = var.expected == sha256("")
    error_message = "unexpected sha256"
  }

}
