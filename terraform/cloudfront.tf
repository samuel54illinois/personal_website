data "aws_route53_zone" "public" {
  name = var.domain

  private_zone = false
}

locals {
  domain_names = [
    var.domain,
    "www.${var.domain}"
  ]
}

module "cdn" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "= v4.0.0"

  aliases = local.domain_names

  comment             = "${var.domain} Site CDN"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  retain_on_delete    = false
  wait_for_deployment = false

  default_root_object = "index.html"

  create_origin_access_control = true
  origin_access_control = {
    (var.domain) = {
      description      = "CloudFront access to S3"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    naked = {
      domain_name = var.domain
      custom_origin_config = {
        http_port                = 80
        https_port               = 443
        origin_keepalive_timeout = 5
        origin_protocol_policy   = "match-viewer"
        origin_ssl_protocols     = ["TLSv1.2"]
      }
    }

    www = {
      domain_name = "www.${var.domain}"
      custom_origin_config = {
        http_port                = 80
        https_port               = 443
        origin_keepalive_timeout = 5
        origin_protocol_policy   = "match-viewer"
        origin_ssl_protocols     = ["TLSv1.2"]
      }
    }

    s3_one = {
      domain_name           = module.site_s3_bucket.s3_bucket_bucket_domain_name
      origin_access_control = var.domain
    }
  }

  default_cache_behavior = {
    target_origin_id       = "naked"
    viewer_protocol_policy = "allow-all"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    query_string    = true
  }

  ordered_cache_behavior = [
    {
      path_pattern           = "*"
      target_origin_id       = "s3_one"
      viewer_protocol_policy = "redirect-to-https"

      allowed_methods = ["GET", "HEAD", "OPTIONS"]
      cached_methods  = ["GET", "HEAD"]
      compress        = true
      query_string    = true
    }
  ]

  viewer_certificate = {
    acm_certificate_arn = aws_acm_certificate.this.arn
    ssl_support_method  = "sni-only"
  }

  tags = var.tags
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain
  subject_alternative_names = ["www.${var.domain}"]

  validation_method = "DNS"

  tags = merge(var.tags,
    {
      Name = var.domain
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "site" {
  for_each = toset(local.domain_names)

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "verify" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}
