import type { ApiChain } from '../api/types';

const RECEIVE_GRADIENT_SVGS: Record<ApiChain, string> = {
  ton: '<svg width="832" height="842" viewBox="0 0 832 842" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_6315_56905)"><path d="M0 0H539L492.314 205.299L439.02 417.049L210 473.75L0 533V0Z" fill="#13EBDD"/><path d="M369.348 201.121L393.5 0H832V351L622 398.267L418.083 454.426L340.623 416.368L369.348 201.121Z" fill="#0099EB"/><path d="M392.979 451.587L621.999 394.886L832 342V842H275.5L339.686 632L392.979 451.587Z" fill="#1345EB"/><path d="M210 471.936L413.917 415.777L510.105 453.835L462.652 632.522L407.5 842H0V528L210 471.936Z" fill="#0099EB"/></g><defs><clipPath id="clip0_6315_56905"><rect width="832" height="842" fill="white"/></clipPath></defs></svg>',

  tron: '<svg width="832" height="842" viewBox="0 0 832 842" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_6318_57254)"><path d="M0 0H539L492.314 205.299L439.02 417.049L210 473.75L0 533V0Z" fill="#EA5313"/><path d="M369.348 201.121L393.5 0H832V351L622 398.267L418.083 454.426L340.623 416.368L369.348 201.121Z" fill="#EA132C"/><path d="M392.979 451.587L621.999 394.886L832 342V842H275.5L339.686 632L392.979 451.587Z" fill="#EA1386"/><path d="M210 471.936L413.917 415.777L510.105 453.835L462.652 632.522L407.5 842H0V528L210 471.936Z" fill="#EA132C"/></g><defs><clipPath id="clip0_6318_57254"><rect width="832" height="842" fill="white"/></clipPath></defs></svg>',

  solana:
    '<svg width="832" height="842" viewBox="0 0 832 842" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_6318_57264)"><path d="M0 0H539L492.314 205.299L439.02 417.049L210 473.75L0 533V0Z" fill="#28E0B9"/><path d="M369.348 201.121L393.5 0H832V351L622 398.267L418.083 454.426L340.623 416.368L369.348 201.121Z" fill="#9945FF"/><path d="M392.979 451.587L621.999 394.886L832 342V842H275.5L339.686 632L392.979 451.587Z" fill="#19FB9B"/><path d="M210 471.936L413.917 415.777L510.105 453.835L462.652 632.522L407.5 842H0V528L210 471.936Z" fill="#9945FF"/></g><defs><clipPath id="clip0_6318_57264"><rect width="832" height="842" fill="white"/></clipPath></defs></svg>',
};

export default RECEIVE_GRADIENT_SVGS;
