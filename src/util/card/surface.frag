#version 300 es
// WebGL version of the iOS card shader `CardBackgroundMotion.metal` from PR #13087.
// The material, the light, the crystal facets and the stars use the same formulas as on iOS.
precision highp float;
uniform sampler2D u_artwork;
uniform sampler2D u_spot0;
uniform sampler2D u_spot1;
uniform sampler2D u_spot2;
uniform sampler2D u_touch;
uniform sampler2D u_brush;
uniform sampler2D u_backdrop;
uniform vec2 size, tilt, touchPosition;
uniform float cornerRadius;
uniform float shine;
uniform vec2 gramShape;
uniform float time, blobTime, seed, intensity, touchOpacity, touchExtent, gramRotation, activity, contrastColor, contrastOpacity;
uniform int materialPreset, customSurface, gram, spotCount, renderPass;
in vec2 v_uv;
out vec4 outputColor;
const float PI=3.141592653589793;

struct CardUniforms {
 vec2 size; float time; float strength; float seed; vec2 materialTilt;
 int customSurface; int shineStyle; float materialEmboss; int materialPreset;
 float materialIntensity; float materialBevel;
 float gramRotation; vec2 telegramShape;
};

float clamp01(float x){return clamp(x,0.0,1.0);}
vec3 clamp01(vec3 x){return clamp(x,0.0,1.0);}
vec3 decode(vec3 c){return mix(pow((c+.055)/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(.04045)));}
vec3 encode(vec3 c){return mix(1.055*pow(max(c,0.0),vec3(1.0/2.4))-.055,c*12.92,lessThanEqual(c,vec3(.0031308)));}

vec2 cardMotionPosition(vec2 position, vec2 size, float time, float amount, float seed) {
    if (amount == 0.0) return position;

    vec2 uv = position / max(size, vec2(1.0));
    vec2 edge = sin(PI * clamp(uv, 0.0, 1.0));
    float envelope = edge.x * edge.y;
    float phase = seed * (2.0 * PI);
    vec2 wave = vec2(
        sin(time * 0.7 + uv.y * 5.0 + phase) - sin(uv.y * 5.0 + phase),
        sin(time * 0.53 + uv.x * 4.0 + phase) - sin(uv.x * 4.0 + phase)
    );

    return position + wave * envelope * amount * size.x / 400.0;
}

// Adapted from `WalletCardBackground.metal` in Telegram-iOS (https://github.com/TelegramMessenger/Telegram-iOS),
// commit f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838, through its iOS port in `CardBackgroundMotion.metal`
float cardTelegramLightField(vec2 uv, CardUniforms u) {
    float aspect = u.size.y / max(u.size.x, 1.0);
    vec2 position = vec2((uv.x - 0.5) * 2.0, (0.5 - uv.y) * 2.0 * aspect);
    float radius = length(position);
    vec2 radial = radius > 0.0001 ? position / radius : vec2(1.0, 0.0);
    vec2 tangent = vec2(-radial.y, radial.x);
    vec2 idleDirection = normalize(vec2(1.0, -aspect));
    float c = cos(u.gramRotation), s = sin(u.gramRotation);
    vec2 keyDirection = vec2(idleDirection.x * c - idleDirection.y * s,
                                idleDirection.x * s + idleDirection.y * c);
    float alignment = dot(tangent, keyDirection);

    // A 120 degree width with an 18 pt blur gives exactly Telegram's light at roughness 0.20
    float widthScale = clamp(u.telegramShape.x, 30.0, 180.0) / 120.0;
    float blur = clamp(u.telegramShape.y, 0.0, 180.0);
    float baseWidth = mix(0.30, 0.44, (0.20 - 0.13) / 0.17) * widthScale;
    float extraBlur = max(0.0, blur - 18.0) / 180.0;
    float wedgeWidth = sqrt(baseWidth * baseWidth + extraBlur * extraBlur);
    float core = exp(-alignment * alignment / max(2.0 * wedgeWidth * wedgeWidth, 0.0001));
    float haloWidth = wedgeWidth * 1.70;
    float halo = exp(-alignment * alignment / max(2.0 * haloWidth * haloWidth, 0.0001));
    float progress = clamp(radius / 0.275, 0.0, 1.0);
    float curve = progress * progress * progress * (progress * (progress * 6.0 - 15.0) + 10.0);
    float centerFade = mix(0.10, 1.0, curve);
    float haloAmount = mix(0.0, 0.42, min(1.0, blur / 18.0));
    float field = mix(core, halo, haloAmount) * centerFade;
    float lobeBalance = mix(0.72, 1.0, 0.5 + 0.5 * dot(radial, keyDirection));

    // The direction is undefined at the very center, so the middle pixels get a flat value and no sharp dot
    float centerAA = smoothstep(0.0, 2.0 / max(u.size.x, 1.0), radius);

    return mix(0.086, field * lobeBalance, centerAA) * baseWidth / wedgeWidth;
}

struct CardCrystalSurface {
    vec3 normal;
    float edge;
};

CardCrystalSurface cardCrystalSurface(vec2 uv) {
    vec2 p = uv * vec2(370.0, 215.0);
    float y = uv.y;
    float outerLeft = -60.0 + 61.250004 * y;
    float outerRight = 430.000031 - 61.250031 * y;
    float innerLeft = 1.0 + 61.333332 * y;
    float innerRight = 369.0 - 61.333344 * y;
    float wingLeft = 62.000008 + 61.499996 * y;
    float wingRight = 307.0 - 61.0 * y;
    float aa = max(fwidth(p.x) + 0.3 * fwidth(p.y), 0.25);
    float outer = smoothstep(-aa, aa, min(p.x - outerLeft, outerRight - p.x));
    float inner = smoothstep(-aa, aa, min(p.x - innerLeft, innerRight - p.x));
    float leftWing = smoothstep(-aa, aa, min(p.x - wingLeft, 185.0 - p.x));
    float rightWing = smoothstep(-aa, aa, min(p.x - 185.0, wingRight - p.x));
    float side = mix(-1.0, 1.0, smoothstep(185.0 - aa, 185.0 + aa, p.x));
    vec2 slope = vec2(side * 0.32, 0.12);
    slope = mix(slope, vec2(-side * 0.18, -0.10), outer);
    slope = mix(slope, vec2(side * 0.12, 0.14), inner);
    slope = mix(slope, vec2(0.29, -0.09), leftWing);
    slope = mix(slope, vec2(-0.26, 0.07), rightWing);

    float edgeDistance = min(min(abs(p.x - innerLeft), abs(p.x - innerRight)),
                            min(min(abs(p.x - wingLeft), abs(p.x - wingRight)), abs(p.x - 185.0)));

    return CardCrystalSurface(normalize(vec3(slope, 1.0)), exp(-edgeDistance / max(0.7, aa)));
}

vec3 cardCrystalArtwork(vec2 uv, CardUniforms u) {
    vec2 position = cardMotionPosition(uv * u.size, u.size, u.time, u.strength, u.seed);

    return decode(texture(u_artwork, position / max(u.size, vec2(1.0))).rgb);
}

vec3 cardMaterial(vec2 uv, vec3 base, CardUniforms u) {
    vec2 step = vec2(1.0/400.0, 1.0/232.0);
    vec3 weights = vec3(0.2126, 0.7152, 0.0722);
    float dx = dot(cardCrystalArtwork(uv + vec2(step.x,0.0),u) - cardCrystalArtwork(uv - vec2(step.x,0.0),u),weights);
    float dy = dot(cardCrystalArtwork(uv + vec2(0.0,step.y),u) - cardCrystalArtwork(uv - vec2(0.0,step.y),u),weights);
    CardCrystalSurface crystal = cardCrystalSurface(uv);
    vec2 slope = (u.customSurface == 0 && u.shineStyle == 0) ? crystal.normal.xy * 0.65 : vec2(0.0);
    slope += clamp(vec2(-dx,-dy) * (1.5 + u.materialEmboss * 8.0), -0.35, 0.35);

    vec3 normal = normalize(vec3(slope, 1.0));
    vec3 view = normalize(vec3(u.materialTilt * 0.65 - (uv-0.5)*vec2(0.3,0.18), 1.4));
    vec3 reflection = reflect(-view, normal);
    vec2 r = reflection.xy;
    float roughness = u.materialPreset == 0 ? 0.28 : (u.materialPreset == 1 ? 0.055 : 0.14);
    vec3 a = vec3(0.78,0.89,1.0), b = vec3(1.0,0.94,0.83), c = vec3(0.62,0.79,1.0);

    vec2 q1 = (r-vec2(-0.25,0.24))/vec2(roughness,0.55);
    vec2 q2 = (r-vec2(0.34,-0.12))/vec2(roughness*0.75,0.44);
    vec2 q3 = (r-vec2(-0.04,-0.42))/vec2(0.58,roughness);
    vec3 radiance = a*exp(-dot(q1,q1)*1.7) + b*exp(-dot(q2,q2)*1.7)*0.75 + c*exp(-dot(q3,q3)*1.7)*0.55;

    if (u.materialPreset == 2) {
        float film = dot(normal,view)*10.0 + dot(r,vec2(3.0,-2.0));
        vec3 pearl = 0.5 + 0.5*cos(film+vec3(0.0,2.094,4.189));
        radiance = radiance*0.7 + pearl*0.18;
    }

    float fresnel = pow(1.0-clamp01(dot(normal,view)),3.0);
    vec3 result = 1.0-(1.0-clamp01(base))*exp(-radiance*u.materialIntensity*(0.5+fresnel*2.0));

    // The bevel line follows the rounded outline in CSS pixels with the DOM corner radius, since the card's aspect
    // ratio can differ from the 400x232 artwork. It scales by width only, so it stays equally thin on all sides.
    float radius = min(cornerRadius, min(u.size.x, u.size.y)*0.5);
    vec2 q = abs((uv-0.5)*u.size)-(u.size*0.5-vec2(radius));
    float sdf = length(max(q,0.0))+min(max(q.x,q.y),0.0)-radius;
    float scale = u.size.x/400.0;
    float edge = exp(-pow((sdf/scale+1.2)/0.8,2.0));
    float inner = (u.customSurface == 0 && u.shineStyle == 0) ? crystal.edge : clamp01(length(vec2(dx,dy))*5.0);
    float directional = 0.25+0.75*clamp01(dot(normalize((uv-0.5)+vec2(0.0001)), normalize(u.materialTilt+vec2(0.2,-0.6))));
    result += (1.0-result) * (edge*directional + inner*max(radiance.r,max(radiance.g,radiance.b))*0.4) * u.materialBevel;

    float relief = dot(vec2(dx,dy),normalize(u.materialTilt+vec2(-0.4,-0.6)))*u.materialEmboss*1.8;
    result += relief*(relief>0.0 ? 1.0-result : result);

    return clamp01(result);
}


vec3 over(vec3 base, vec4 spot){return spot.rgb+base*(1.0-spot.a);}

vec2 blobUV(vec2 uv){
 vec2 p=uv*vec2(400,232)-vec2(200,116);
 float a=blobTime*.7*2.0*PI/40.0,c=cos(a),s=sin(a);

 return (vec2(c*p.x+s*p.y,-s*p.x+c*p.y)+vec2(200,116)+128.0)/vec2(656,488);
}

const vec2 stars[20]=vec2[](vec2(30,28),vec2(74,18),vec2(127,30),vec2(211,18),vec2(293,24),vec2(368,32),vec2(344,63),vec2(26,85),vec2(379,119),vec2(27,147),vec2(59,179),vec2(28,214),vec2(101,209),vec2(170,214),vec2(238,209),vec2(316,212),vec2(370,154),vec2(340,165),vec2(377,69),vec2(85,56));
const float radii[20]=float[](6.0,3.0,4.0,2.5,3.0,8.0,3.5,4.0,5.0,3.0,7.5,3.0,4.5,3.0,2.5,4.0,6.0,3.5,4.0,3.0);

void main(){
 CardUniforms u;
 u.size=size;u.time=time;u.strength=customSurface==1?15.0:0.0;u.seed=seed;
 u.materialTilt=tilt;u.customSurface=customSurface;u.shineStyle=gram==1?3:0;
 u.materialEmboss=.4;u.materialPreset=materialPreset;
 u.materialIntensity=intensity;u.materialBevel=.4;
 u.gramRotation=gramRotation;u.telegramShape=gramShape;

 vec2 uv=v_uv;
 vec3 color;

 if(renderPass==2){
  // The backdrop is a WebGL render, so its rows start at the bottom, while `uv` starts at the top
  color=texture(u_backdrop,vec2(uv.x,1.0-uv.y)).rgb;
 }else{
  vec2 materialUV=uv+tilt*3.5*.45/size*sin(PI*uv.x)*sin(PI*uv.y);
  vec2 position=cardMotionPosition(materialUV*size,size,time,u.strength,seed);
  color=texture(u_artwork,position/size).rgb;

  vec2 buv=blobUV(uv);
  if(spotCount>0)color=over(color,texture(u_spot0,buv));
  if(spotCount>1)color=over(color,texture(u_spot1,buv));
  if(spotCount>2)color=over(color,texture(u_spot2,buv));

  if(contrastColor>=0.0){
   float radius=length((uv-.5)*vec2(400,232)/vec2(269.69,158));
   float a=radius<.25?1.0-radius*.8:radius<.75?1.1-radius*1.2:max(0.0,.8-radius*.8);
   vec3 overlay=mix(1.0-2.0*(1.0-color)*(1.0-contrastColor),2.0*color*contrastColor,lessThanEqual(color,vec3(.5)));
   color=mix(color,overlay,a*contrastOpacity);color=mix(color,vec3(contrastColor),a*.16);
  }

  if(gram==1){
   float grain=texture(u_brush,uv).r;
   vec3 brushed=mix(1.0-2.0*(1.0-color)*(1.0-grain),2.0*color*grain,lessThanEqual(color,vec3(.5)));
   color=mix(color,brushed,.15);

   float field=cardTelegramLightField(uv,u);
   color=clamp01(encode(decode(color)+vec3(.090,.565,.965)*field*(.32/.24)*shine));
  }

  vec2 tuv=((uv-.5)*size-touchPosition*size*.5)/touchExtent+.5;

  if(all(greaterThanEqual(tuv,vec2(0)))&&all(lessThanEqual(tuv,vec2(1))))
   color=clamp01(color+texture(u_touch,tuv).a*touchOpacity*.7);

  color=cardMaterial(uv,color,u);
 }

 if(gram==1&&renderPass!=1){
  vec2 artworkPosition=uv*vec2(400,232);
  vec2 pixel=fwidth(artworkPosition);

  for(int i=0;i<20;i++){
   // The light field below is the same for every pixel of a star, so pixels outside the star's reach skip it.
   // A star radius is at most `1.55 * radii[i]`, and `reach * reach` also covers the smoothing width `aa`.
   vec2 offset=artworkPosition-stars[i];
   float reach=sqrt(radii[i]*1.55)+sqrt(pixel.x)+sqrt(pixel.y);
   if(max(abs(offset.x),abs(offset.y))>reach*reach)continue;

   float phase=float(i)*2.3999632;
   float twinkle=smoothstep(.15,1.0,.5+.5*sin(blobTime*(.28+fract(phase)*.14)+phase));
   float field=cardTelegramLightField(stars[i]/vec2(400,232),u);
   float activation=field*min(1.0,shine*5.0)*(.35+.65*activity);
   float radius=radii[i]*(.15+.85*twinkle+.45*activation+.1*activity);
   float inside=shine>0.0?smoothstep(.05,.75,field):0.0;
   radius*=mix(.5,1.0,inside);

   float opacity=clamp01(twinkle*.65+activation*.7+activity*.12)*mix(.5,1.0,inside);
   vec2 local=abs(offset/radius);
   vec2 cell=pixel/radius;
   float d=sqrt(local.x)+sqrt(local.y);

   // The same width as `fwidth(d)`, taken from the change of `d` over one pixel on each axis. Derivatives are
   // undefined after the `continue` above, since the neighboring pixels may have skipped this star.
   float aa=max(sqrt(local.x+cell.x)-sqrt(local.x)+sqrt(local.y+cell.y)-sqrt(local.y),.02);
   float alpha=(1.0-smoothstep(1.0-aa,1.0+aa,d))*opacity;
   vec3 soft=mix(sqrt(max(color,0.0)),((16.0*color-12.0)*color+4.0)*color,lessThanEqual(color,vec3(.25)));

   // Blend in linear color, the way iOS blends into its sRGB render target
   color=encode(mix(decode(color),decode(soft),alpha));
  }
 }

 outputColor=vec4(color,1);
}
