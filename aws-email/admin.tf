################################################################################
# Admin site — S3 + CloudFront + ACM (us-east-1) + Route53 alias
#
# Sirve el panel estático del admin en https://admin.bubabeautystudio.com.
# El bucket es privado; CloudFront accede via Origin Access Control (OAC).
################################################################################

resource "aws_s3_bucket" "admin" {
  bucket = "${local.name_prefix}-admin-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "admin" {
  bucket = aws_s3_bucket.admin.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "admin" {
  bucket                  = aws_s3_bucket.admin.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "admin" {
  bucket = aws_s3_bucket.admin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "admin" {
  bucket = aws_s3_bucket.admin.id

  versioning_configuration {
    status = "Enabled"
  }
}

################################################################################
# ACM certificate (us-east-1 obligatorio para CloudFront) + validación DNS
################################################################################

resource "aws_acm_certificate" "admin" {
  provider = aws.us_east_1

  domain_name       = local.admin_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.admin.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.root.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "admin" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.admin.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

################################################################################
# CloudFront distribution
################################################################################

resource "aws_cloudfront_origin_access_control" "admin" {
  name                              = "${local.name_prefix}-admin-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Function que reescribe URLs sin extensión a /index.html
# (para que http://admin.../ funcione sin redirecciones).
resource "aws_cloudfront_function" "admin_rewrite" {
  name    = "${local.name_prefix}-admin-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var req = event.request;
      var uri = req.uri;
      if (uri.endsWith('/')) {
        req.uri = uri + 'index.html';
      } else if (!uri.includes('.')) {
        req.uri = uri + '/index.html';
      }
      return req;
    }
  JS
}

resource "aws_cloudfront_distribution" "admin" {
  enabled             = true
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100" # Europa + NA (más barato)
  aliases             = [local.admin_fqdn]
  http_version        = "http2and3"
  comment             = "Admin panel Buba Beauty Studio (${var.environment})"

  origin {
    domain_name              = aws_s3_bucket.admin.bucket_regional_domain_name
    origin_id                = "s3-admin"
    origin_access_control_id = aws_cloudfront_origin_access_control.admin.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-admin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.admin.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.admin_rewrite.arn
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.admin.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Security headers: CSP minimalista, X-Frame-Options, referrer policy.
resource "aws_cloudfront_response_headers_policy" "admin" {
  name = "${local.name_prefix}-admin-security"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com data:",
        "img-src 'self' data: https:",
        "connect-src 'self' ${aws_apigatewayv2_api.main.api_endpoint} https://${aws_cognito_user_pool_domain.admin.domain}.auth.${var.aws_region}.amazoncognito.com https://cognito-idp.${var.aws_region}.amazonaws.com",
        "frame-src 'self'",
      ])
      override = true
    }
  }
}

# Bucket policy: solo CloudFront via OAC puede leer.
resource "aws_s3_bucket_policy" "admin" {
  bucket = aws_s3_bucket.admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOACRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.admin.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.admin.arn
        }
      }
    }]
  })
}

################################################################################
# Route53 alias admin.<root> → CloudFront
################################################################################

resource "aws_route53_record" "admin" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.admin_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.admin.domain_name
    zone_id                = aws_cloudfront_distribution.admin.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin_ipv6" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.admin_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.admin.domain_name
    zone_id                = aws_cloudfront_distribution.admin.hosted_zone_id
    evaluate_target_health = false
  }
}
