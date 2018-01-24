﻿#ifndef UNITY_VOLUMEPROJECTION_INCLUDED
#define UNITY_VOLUMEPROJECTION_INCLUDED

#define ENVMAP_FEATURE_PERFACEINFLUENCE
#define ENVMAP_FEATURE_PERFACEFADE
#define ENVMAP_FEATURE_INFLUENCENORMAL

#include "../LightDefinition.cs.hlsl"

float3x3 WorldToProxySpace(EnvProxyData proxyData)
{
    return transpose(float3x3(proxyData.right, proxyData.up, proxyData.forward)); // worldToLocal assume no scaling
}

float3 WorldToProxyPosition(EnvProxyData proxyData, float3x3 worldToPS, float3 positionWS)
{
    float3 positionPS = positionWS - proxyData.positionWS;
    positionPS = mul(positionPS, worldToPS).xyz;
    return positionPS;
}

float IntersectSphereProxy(EnvProxyData proxyData, float3 dirPS, float3 positionPS)
{
    float sphereOuterDistance = proxyData.extents.x;
    float projectionDistance = IntersectRaySphereSimple(positionPS, dirPS, sphereOuterDistance);
    projectionDistance = max(projectionDistance, proxyData.minProjectionDistance); // Setup projection to infinite if requested (mean no projection shape)

    return projectionDistance;
}

float IntersectBoxProxy(EnvProxyData proxyData, float3 dirPS, float3 positionPS)
{
    float3 boxOuterDistance = proxyData.extents;
    float projectionDistance = IntersectRayAABBSimple(positionPS, dirPS, -boxOuterDistance, boxOuterDistance);
    projectionDistance = max(projectionDistance, proxyData.minProjectionDistance); // Setup projection to infinite if requested (mean no projection shape)

    return projectionDistance;
}

float InfluenceSphereWeight(EnvLightData lightData, BSDFData bsdfData, float3 positionWS, float3 positionLS, float3 dirLS)
{
    float lengthPositionLS = length(positionLS);
    float sphereInfluenceDistance = lightData.influenceExtents.x - lightData.blendDistancePositive.x;
    float distFade = max(lengthPositionLS - sphereInfluenceDistance, 0.0);
    float alpha = saturate(1.0 - distFade / max(lightData.blendDistancePositive.x, 0.0001)); // avoid divide by zero

#if defined(ENVMAP_FEATURE_INFLUENCENORMAL)
    float insideInfluenceNormalVolume = lengthPositionLS <= (lightData.influenceExtents.x - lightData.blendNormalDistancePositive.x) ? 1.0 : 0.0;
    float insideWeight = InfluenceFadeNormalWeight(bsdfData.normalWS, normalize(positionWS - lightData.capturePositionWS));
    alpha *= insideInfluenceNormalVolume ? 1.0 : insideWeight;
#endif

    return alpha;
}

float InfluenceBoxWeight(EnvLightData lightData, BSDFData bsdfData, float3 positionWS, float3 positionLS, float3 dirLS)
{
    float3 boxOuterDistance = lightData.influenceExtents;
    // 2. Process the position influence
    // Calculate falloff value, so reflections on the edges of the volume would gradually blend to previous reflection.
#if defined(ENVMAP_FEATURE_PERFACEINFLUENCE) || defined(ENVMAP_FEATURE_INFLUENCENORMAL) || defined(ENVMAP_FEATURE_PERFACEFADE)
    // Distance to each cube face
    float3 negativeDistance = boxOuterDistance + positionLS;
    float3 positiveDistance = boxOuterDistance - positionLS;
#endif

#if defined(ENVMAP_FEATURE_PERFACEINFLUENCE)
    // Influence falloff for each face
    float3 negativeFalloff = negativeDistance / max(0.0001, lightData.blendDistanceNegative);
    float3 positiveFalloff = positiveDistance / max(0.0001, lightData.blendDistancePositive);

    // Fallof is the min for all faces
    float influenceFalloff = min(
        min(min(negativeFalloff.x, negativeFalloff.y), negativeFalloff.z),
        min(min(positiveFalloff.x, positiveFalloff.y), positiveFalloff.z));

    float alpha = saturate(influenceFalloff);
#else
    float distFace = DistancePointBox(positionLS, -lightData.influenceExtents + lightData.blendDistancePositive.x, lightData.influenceExtents - lightData.blendDistancePositive.x);
    float alpha = saturate(1.0 - distFace / max(lightData.blendDistancePositive.x, 0.0001));
#endif

#if defined(ENVMAP_FEATURE_INFLUENCENORMAL)
    // 3. Process the normal influence
    // Calculate a falloff value to discard normals pointing outward the center of the environment light
    float3 belowPositiveInfluenceNormalVolume = positiveDistance / max(0.0001, lightData.blendNormalDistancePositive);
    float3 aboveNegativeInfluenceNormalVolume = negativeDistance / max(0.0001, lightData.blendNormalDistanceNegative);
    float insideInfluenceNormalVolume = all(belowPositiveInfluenceNormalVolume >= 1.0) && all(aboveNegativeInfluenceNormalVolume >= 1.0) ? 1.0 : 0;
    float insideWeight = InfluenceFadeNormalWeight(bsdfData.normalWS, normalize(positionWS - lightData.capturePositionWS));
    alpha *= insideInfluenceNormalVolume ? 1.0 : insideWeight;
#endif

#if defined(ENVMAP_FEATURE_PERFACEFADE)
    // 4. Fade specific cubemap faces
    // For each axes (both positive and negative ones), we want to fade from the center of one face to another
    // So we normalized the sample direction (R) and use its component to fade for each axis
    // We consider R.x as cos(X) and then fade as angle from 60°(=acos(1/2)) to 75°(=acos(1/4))
    // For positive axes: axisFade = (R - 1/4) / (1/2 - 1/4)
    // <=> axisFace = 4 * R - 1;
    float3 faceFade = saturate((4 * dirLS - 1) * lightData.boxSideFadePositive) + saturate((-4 * dirLS - 1) * lightData.boxSideFadeNegative);
    alpha *= saturate(faceFade.x + faceFade.y + faceFade.z);
#endif

    return alpha;
}



float3x3 WorldToLightSpace(EnvLightData lightData)
{
    return transpose(float3x3(lightData.right, lightData.up, lightData.forward)); // worldToLocal assume no scaling
}

float3 WorldToLightPosition(EnvLightData lightData, float3x3 worldToLS, float3 positionWS)
{
    float3 positionLS = positionWS - lightData.positionWS;
    positionLS = mul(positionLS, worldToLS).xyz;
    return positionLS;
}

#endif // UNITY_VOLUMEPROJECTION_INCLUDED