function [u,identity]=sht_sobol_points(d,count,skip,seed)
%SHT_SOBOL_POINTS 无工具箱Sobol积分点，53位、标准二进制索引顺序。
% 采用Joe/Kuo 2003的1111维方向数，沿用旧sobolset的方向数来源。
% seed非空时施加GF(2)下三角线性扰乱及独立数字移位；空seed为未扰乱。
% 这是相同类型的QMC规则，不承诺与MathWorks内部扰乱随机位逐位一致。
% 局部RandStream不改调用方rng；缓存最近同配置点集以避免重复生成。
%
% Direction-number data copyright (c) 2008, Frances Y. Kuo and Stephen Joe.
% All rights reserved. Redistribution and use in source and binary forms,
% with or without modification, are permitted provided that:
% * Source distributions retain this copyright, conditions and disclaimer.
% * Binary distributions reproduce them in documentation/other materials.
% * Names of the copyright holders, University of New South Wales,
%   University of Waikato or contributors may not endorse derived products
%   without specific prior written permission.
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY EXPRESS
% OR IMPLIED WARRANTIES, INCLUDING MERCHANTABILITY AND FITNESS FOR A
% PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
% OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
% EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING PROCUREMENT OF SUBSTITUTE
% GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
% OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
% DAMAGE. Source: https://web.maths.unsw.edu.au/~fkuo/sobol/
if nargin<3,skip=0;end
if nargin<4,seed=[];end
validateattributes(d,{'numeric'},{'scalar','integer','>=',1,'<=',1111});
validateattributes(count,{'numeric'},{'scalar','integer','positive'});
validateattributes(skip,{'numeric'},{'scalar','integer','nonnegative'});
assert(count+skip<=flintmax,'SHT:Sobol:Index','索引超出53位精确整数范围。');
if ~isempty(seed),validateattributes(seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});end
persistent oldKey oldPoints directions
key=[d,count,skip,seed];identity='joe_kuo_2003_standard53_lms_shift_v1';
if isequal(key,oldKey),u=oldPoints;return;end
bits=53;
if isempty(directions) || size(directions,1)<d
    directions=local_directions(d,bits);
end
v=directions(1:d,:);shift=zeros(d,1,'uint64');
if ~isempty(seed)
    stream=RandStream('mt19937ar','Seed',seed);
    for j=1:d
        % 二进制小数从最高有效位开始排列；单位对角保证扰乱矩阵可逆。
        L=tril(rand(stream,bits,bits)<.5,-1)+eye(bits);binary=zeros(bits,bits);
        for r=1:bits,binary(r,:)=bitget(v(j,:),bits-r+1);end
        transformed=mod(L*binary,2);new=zeros(1,bits,'uint64');
        for r=1:bits,new=bitor(new,bitshift(uint64(transformed(r,:)),bits-r));end
        v(j,:)=new;shift(j)=uint64(floor(rand(stream)*2^bits));
    end
end
index=uint64(skip+(0:count-1).');u=zeros(count,d);
for j=1:d
    value=repmat(shift(j),count,1);
    for r=1:bits
        mask=bitget(index,r)>0;
        if any(mask),value(mask)=bitxor(value(mask),v(j,r));end
    end
    u(:,j)=double(value)*2^-bits;
end
oldKey=key;oldPoints=u;
end

function v=local_directions(d,bits)
file=fullfile(fileparts(mfilename('fullpath')),'TestData','compatibility','joe-kuo-old.1111');
fid=fopen(file,'rt');assert(fid>=0,'SHT:Sobol:Data','缺少Sobol方向数：%s。',file);
cleanup=onCleanup(@()fclose(fid));fgetl(fid);v=zeros(d,bits,'uint64');
v(1,:)=bitshift(uint64(ones(1,bits)),bits-(1:bits));
for j=2:d
    row=sscanf(fgetl(fid),'%f').';s=row(2);a=uint64(row(3));
    assert(row(1)==j && numel(row)==3+s,'SHT:Sobol:Data','Sobol方向数格式错误。');
    for r=1:s,v(j,r)=bitshift(uint64(row(3+r)),bits-r);end
    for r=s+1:bits
        value=bitxor(v(j,r-s),bitshift(v(j,r-s),-s));
        for k=1:s-1
            if bitget(a,s-k),value=bitxor(value,v(j,r-k));end
        end
        v(j,r)=value;
    end
end
clear cleanup;
end
