data "aws_iam_policy_document" "eks_ecr" {
    statement {
        sid = "EKSECRACCESS"
        effect = "Allow"
        actions= [
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:BatchGetImage",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:GetAuthorizationToken"
                ]
        resources = ["*"]
        }
 }
 